"""DynamoDB-backed implementation of the Cowlog API. No cloud calls at import."""
from __future__ import annotations
import base64
import hashlib
import hmac
import json
import logging
import os
import re
from datetime import datetime, timedelta
from decimal import Decimal
from urllib.parse import unquote

import boto3
from boto3.dynamodb.conditions import Key
from boto3.dynamodb.types import TypeSerializer
from botocore.exceptions import ClientError
from app import normalized_record, classify, parse_time, iso, utcnow, JST, MAX_BODY

LOG = logging.getLogger(__name__)
STYLES = ('unknown', 'holstein', 'brown')
FIELDS = ('device_id','stream_id','seq','measured_at','received_at','ingested_at',
          'latitude','longitude','gps_accuracy_m','activity_seconds','coverage_seconds',
          'interval_seconds','battery_percent','hdop','satellites')

class Conflict(ValueError): pass
class TooLarge(ValueError): pass

def device_id(value):
    if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}',value):
        raise ValueError('invalid device_id')
    return value

def number_value(value):
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]{1,12}',value):
        raise ValueError('number must contain 1 to 12 ASCII digits')
    return value

def decimalize(value):
    return json.loads(json.dumps(value,allow_nan=False),parse_float=Decimal)

def plain(value):
    if isinstance(value,Decimal): return int(value) if value == value.to_integral_value() else float(value)
    if isinstance(value,dict): return {k:plain(v) for k,v in value.items()}
    if isinstance(value,list): return [plain(v) for v in value]
    return value

def conditional(exc):
    code=exc.response['Error']['Code']
    return code=='ConditionalCheckFailedException' or (code=='TransactionCanceledException' and any(r.get('Code')=='ConditionalCheckFailed' for r in exc.response.get('CancellationReasons',[])))

class Store:
    def __init__(self, resource=None):
        self.db = resource or boto3.resource('dynamodb')
        self.registry = self.db.Table(os.environ['REGISTRY_TABLE'])
        self.measurements = self.db.Table(os.environ['MEASUREMENTS_TABLE'])
        self.areas = self.db.Table(os.environ['AREAS_TABLE'])
        self.farm = os.environ['FARM_ID']
        self.pk = 'FARM#'+self.farm
        # A separate low-level client avoids resource-level input serialization hooks.
        self.client = boto3.client('dynamodb',region_name=self.db.meta.client.meta.region_name)

    def _key(self,device): return {'pk':self.pk,'sk':'COLLAR#'+device}
    def _number_key(self,number): return {'pk':self.pk,'sk':'NUMBER#'+number}
    def _stream(self,device): return self.pk+'#DEVICE#'+device
    def get(self,device):
        return plain(self.registry.get_item(Key=self._key(device),ConsistentRead=True).get('Item'))
    def list(self):
        args={'KeyConditionExpression':Key('pk').eq(self.pk)&Key('sk').begins_with('COLLAR#'),'ConsistentRead':True}
        items=[]
        while True:
            page=self.registry.query(**args);items.extend(page.get('Items',[]))
            if len(items)>100: raise TooLarge('dashboard supports up to 100 registered collars in this prototype')
            if 'LastEvaluatedKey' not in page: break
            args['ExclusiveStartKey']=page['LastEvaluatedKey']
        return plain(items)
    def _tx(self,ops):
        serializer=TypeSerializer()
        prepared=[]
        for operation in ops:
            op={k:dict(v) for k,v in operation.items()}
            body=next(iter(op.values()))
            for field in ('Item','Key','ExpressionAttributeValues'):
                if field in body: body[field]={k:serializer.serialize(v) for k,v in decimalize(body[field]).items()}
            prepared.append(op)
        self.client.transact_write_items(TransactItems=prepared)

    def create_collar(self,device,number,style='unknown'):
        device=device_id(device);number=number_value(number)
        if style not in STYLES: raise ValueError('invalid cow style')
        item={**self._key(device),'device_id':device,'number':number,'cow_style':style,'version':1,'created_at':iso(utcnow())}
        try:
            self._tx([
                {'Put':{'TableName':self.registry.name,'Item':item,'ConditionExpression':'attribute_not_exists(pk)'}},
                {'Put':{'TableName':self.registry.name,'Item':{**self._number_key(number),'device_id':device},'ConditionExpression':'attribute_not_exists(pk)'}},
                {'Update':{'TableName':self.registry.name,'Key':{'pk':self.pk,'sk':'LIMITS'},'UpdateExpression':'ADD collar_count :one','ConditionExpression':'attribute_not_exists(collar_count) OR collar_count < :limit','ExpressionAttributeValues':{':one':1,':limit':100}}},
            ])
        except ClientError as exc:
            if conditional(exc):
                current=self.get(device)
                if current and current['number']==number and current['cow_style']==style:
                    return {'device_id':device,'number':number,'cow_style':style,'saved_to':'server','created':False}
                limit=self.registry.get_item(Key={'pk':self.pk,'sk':'LIMITS'},ConsistentRead=True).get('Item',{})
                if limit.get('collar_count',0)>=100: raise TooLarge('prototype registration limit is 100 collars') from exc
                raise Conflict('collar or number already registered') from exc
            raise
        return {'device_id':device,'number':number,'cow_style':style,'saved_to':'server','created':True}

    def set_number(self,device,body):
        device=device_id(device);number=number_value(body.get('number'))
        if 'expected_number' not in body: raise ValueError('expected_number is required')
        current=self.get(device)
        if current is None: raise LookupError('collar not found')
        style=body.get('cow_style',current['cow_style'])
        if style not in STYLES: raise ValueError('invalid cow style')
        result={'device_id':device,'number':number,'cow_style':style,'saved_to':'server'}
        if current['number']==number and current['cow_style']==style: return result
        if current['number']!=body['expected_number'] or ('cow_style' in body and current['cow_style']!=body.get('expected_style')):
            raise Conflict('collar changed; reload before saving')
        ops=[{'Update':{'TableName':self.registry.name,'Key':self._key(device),
            'UpdateExpression':'SET #n=:n, cow_style=:s, version=version+:one',
            'ConditionExpression':'version=:v','ExpressionAttributeNames':{'#n':'number'},
            'ExpressionAttributeValues':{':n':number,':s':style,':v':current['version'],':one':1}}}]
        if current['number']!=number:
            ops.extend([
                {'Put':{'TableName':self.registry.name,'Item':{**self._number_key(number),'device_id':device},'ConditionExpression':'attribute_not_exists(pk)'}},
                {'Delete':{'TableName':self.registry.name,'Key':self._number_key(current['number']),
                           'ConditionExpression':'device_id=:d','ExpressionAttributeValues':{':d':device}}},
            ])
        try: self._tx(ops)
        except ClientError as exc:
            if conditional(exc): raise Conflict('number in use or collar changed') from exc
            raise
        return result

    def ingest(self,raw_records,now=None):
        now=now or utcnow()
        if not isinstance(raw_records,list) or not 1<=len(raw_records)<=100: raise ValueError('records must contain 1 to 100 items')
        records=[dict(zip(FIELDS,normalized_record(r,now))) for r in raw_records]
        for record in records:
            device_id(record['device_id'])
            if self.get(record['device_id']) is None: raise LookupError('register collar before ingesting')
        accepted=0
        for record in records:
            device=record['device_id'];identity=f"{record['stream_id']:010d}#{record['seq']:010d}"
            payload={k:v for k,v in record.items() if k not in ('ingested_at','received_at')}
            digest=hashlib.sha256(json.dumps(plain(decimalize(payload)),sort_keys=True,separators=(',',':')).encode()).hexdigest()
            pk=self._stream(device)
            duplicate_key={'device_id':pk,'record_key':'D#'+identity}
            try:
                self._tx([
                    {'Put':{'TableName':self.measurements.name,'Item':{**duplicate_key,'digest':digest},'ConditionExpression':'attribute_not_exists(device_id)'}},
                    {'Put':{'TableName':self.measurements.name,'Item':{'device_id':pk,'record_key':'T#'+record['measured_at']+'#'+identity,'data':record},'ConditionExpression':'attribute_not_exists(device_id)'}},
                ])
                accepted+=1
            except ClientError as exc:
                if not conditional(exc): raise
                previous=self.measurements.get_item(Key=duplicate_key,ConsistentRead=True).get('Item')
                if not previous: raise
                if previous['digest']!=digest: raise Conflict('measurement identity reused with different content') from exc
            # Also repair caches when a retry follows a successful history write.
            self._latest(device,'latest_at','latest_data',record)
            if record['latitude'] is not None and (record['gps_accuracy_m'] is None or record['gps_accuracy_m']<=100):
                self._latest(device,'fix_at','fix_data',record)
        return {'accepted':accepted,'duplicates':len(records)-accepted}

    def _latest(self,device,time_field,data_field,record):
        try:
            self.registry.update_item(Key=self._key(device),UpdateExpression='SET #t=:t, #d=:d, #o=:o',
                ConditionExpression='attribute_exists(pk) AND (attribute_not_exists(#o) OR #o<:o)',
                ExpressionAttributeNames={'#t':time_field,'#d':data_field,'#o':time_field+'_order'},
                ExpressionAttributeValues=decimalize({':t':record['measured_at'],':d':record,':o':record['measured_at']+f"#{record['stream_id']:010d}#{record['seq']:010d}"}))
        except ClientError as exc:
            if not conditional(exc): raise

    def rows(self,device,start,end):
        args={'KeyConditionExpression':Key('device_id').eq(self._stream(device))&Key('record_key').between('T#'+iso(start),'T#'+iso(end)),'ConsistentRead':True}
        output=[]
        while True:
            page=self.measurements.query(**args);output.extend(i['data'] for i in page.get('Items',[]))
            if len(output)>10000: raise TooLarge('too many records; use a coarser measurement interval')
            if 'LastEvaluatedKey' not in page: break
            args['ExclusiveStartKey']=page['LastEvaluatedKey']
        return plain(output)

    def dashboard(self,now=None):
        now=now or utcnow();out=[]
        for collar in self.list():
            device=collar['device_id'];rows=[]
            for days in range(8):
                end=now-timedelta(days=days)
                rows.extend(self.rows(device,end-timedelta(hours=2),end+timedelta(seconds=1)))
            latest=collar.get('latest_data')
            if latest: rows.append(latest)
            rows=list({(r['stream_id'],r['seq']):r for r in rows}.values())
            status,reason,ratio=classify(rows,now)
            fix=collar.get('fix_data')
            out.append({'id':device,'device_id':device,'name':collar['number'],'number':collar['number'],
                'cow_style':collar['cow_style'],'status':status,'reason':reason,'activity_ratio':ratio,
                'latest_measured_at':latest['measured_at'] if latest else None,
                'battery_percent':latest['battery_percent'] if latest else None,
                'latest_position':({'latitude':fix['latitude'],'longitude':fix['longitude'],'measured_at':fix['measured_at'],
                    'accuracy_m':fix['gps_accuracy_m'],'hdop':fix['hdop'],'satellites':fix['satellites']} if fix else None)})
        priority={'check':0,'disconnected':1,'insufficient':2,'no_data':3,'learning':4,'normal':5}
        out.sort(key=lambda c:(priority[c['status']],c['number']))
        return {'generated_at':iso(now),'cows':out}

    def history(self,device,day):
        device=device_id(device)
        if self.get(device) is None: raise LookupError('collar not found')
        try: start=datetime.strptime(day,'%Y-%m-%d').replace(tzinfo=JST)
        except (ValueError,TypeError) as exc: raise ValueError('date must be YYYY-MM-DD') from exc
        return {'cow_id':device,'date':day,'measurements':self.rows(device,start,start+timedelta(days=1))}

    def farm_areas(self):
        item=self.areas.get_item(Key={'farm_id':self.farm,'area_id':'BOUNDARIES'},ConsistentRead=True).get('Item')
        if item is None: raise LookupError('farm areas have not been imported')
        return plain(item['geojson'])


def handler(event,context,store=None):
    """HTTP API v2 Lambda proxy. Prototype's three separate bearer credentials."""
    def reply(status,payload):
        return {'statusCode':status,'headers':{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'},
                'body':json.dumps(plain(payload),ensure_ascii=False,allow_nan=False)}
    request_id=getattr(context,'aws_request_id','local')
    try:
        method=event.get('requestContext',{}).get('http',{}).get('method','')
        path=event.get('rawPath','')
        stage=event.get('requestContext',{}).get('stage','$default')
        if stage!='$default' and path.startswith('/'+stage+'/'): path=path[len(stage)+1:]
        parts=path.strip('/').split('/')
        role = 'READ' if method=='GET' else 'INGEST' if (method,path)==('POST','/v1/measurements') else 'MANAGE'
        headers={k.lower():v for k,v in (event.get('headers') or {}).items()}
        token=os.environ.get('COWLOG_'+role+'_TOKEN','')
        supplied=headers.get('authorization','')
        if not token or not isinstance(supplied,str) or not hmac.compare_digest(supplied.encode(),('Bearer '+token).encode()):
            return reply(401,{'error':'unauthorized'})
        tokens=[os.environ.get('COWLOG_'+r+'_TOKEN','') for r in ('READ','INGEST','MANAGE')]
        if any(not t for t in tokens) or len(set(tokens))!=3:
            return reply(503,{'error':'credentials are not configured separately'})
        body={}
        if method in ('POST','PUT'):
            raw=event.get('body') or ''
            raw=base64.b64decode(raw,validate=True) if event.get('isBase64Encoded') else raw.encode()
            if not 0<len(raw)<=MAX_BODY: raise ValueError('invalid body size')
            body=json.loads(raw)
            if not isinstance(body,dict): raise ValueError('body must be an object')
        store=store or Store()
        if (method,path)==('GET','/v1/dashboard'): return reply(200,store.dashboard())
        if (method,path)==('GET','/v1/collars'):
            return reply(200,{'collars':[{'device_id':c['device_id'],'number':c['number'],'cow_style':c['cow_style'],'last_seen_at':c.get('latest_at')} for c in store.list()]})
        if (method,path)==('POST','/v1/collars'):
            result=store.create_collar(body.get('device_id'),body.get('number'),body.get('cow_style','unknown'))
            return reply(201 if result['created'] else 200,result)
        if (method,path)==('POST','/v1/measurements'): return reply(200,store.ingest(body.get('records')))
        if (method,path)==('GET','/v1/farm/areas'): return reply(200,store.farm_areas())
        if len(parts)==4 and parts[:2]==['v1','collars'] and parts[3]=='number' and method=='PUT':
            return reply(200,store.set_number(unquote(parts[2]),body))
        if len(parts)==4 and parts[:2]==['v1','cows'] and parts[3]=='history' and method=='GET':
            return reply(200,store.history(unquote(parts[2]),(event.get('queryStringParameters') or {}).get('date','')))
        return reply(404,{'error':'not found'})
    except Conflict as exc: return reply(409,{'error':str(exc)})
    except TooLarge as exc: return reply(413,{'error':str(exc)})
    except KeyError:
        LOG.error('Cowlog missing configuration or stored field request_id=%s',request_id)
        return reply(503,{'error':'temporarily unavailable','request_id':request_id})
    except LookupError as exc: return reply(404,{'error':str(exc)})
    except (ValueError,TypeError,UnicodeError) as exc: return reply(400,{'error':str(exc)})
    except Exception:
        # Never log event/body/headers; these can contain device data and tokens.
        LOG.exception('Cowlog backend failed request_id=%s',request_id)
        return reply(503,{'error':'temporarily unavailable','request_id':request_id})
