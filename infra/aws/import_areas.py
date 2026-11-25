"""Import reviewed GeoJSON to the AWS area table; never runs during app build."""
import argparse,hashlib,json,math
from pathlib import Path
from decimal import Decimal
import boto3

def validate(data):
    if not isinstance(data,dict) or data.get('type')!='FeatureCollection': raise ValueError('FeatureCollection required')
    features=data.get('features')
    if not isinstance(features,list) or not 1<=len(features)<=32: raise ValueError('1 to 32 features required')
    ids=set()
    for f in features:
        if f.get('type')!='Feature' or f.get('geometry',{}).get('type')!='Polygon': raise ValueError('Polygon features only')
        identity=f.get('properties',{}).get('id')
        if not isinstance(identity,str) or identity in ids: raise ValueError('unique string area IDs required')
        ids.add(identity)
        rings=f['geometry'].get('coordinates')
        if not isinstance(rings,list) or len(rings)!=1: raise ValueError('one exterior ring per feature required')
        ring=rings[0]
        if not isinstance(ring,list) or not 4<=len(ring)<=1001 or ring[0]!=ring[-1]: raise ValueError('closed polygon ring required')
        for pair in ring:
            if not isinstance(pair,list) or len(pair)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) for v in pair): raise ValueError('finite longitude/latitude required')
            if not -180<=pair[0]<=180 or not -90<=pair[1]<=90: raise ValueError('coordinate out of range')
    if len(json.dumps(data,ensure_ascii=False).encode())>300000: raise ValueError('GeoJSON too large')
    return data

def main():
    p=argparse.ArgumentParser();p.add_argument('--stack',required=True);p.add_argument('--geojson',required=True);p.add_argument('--region',default='ap-northeast-1');p.add_argument('--replace',action='store_true')
    args=p.parse_args();data=validate(json.loads(Path(args.geojson).read_text()))
    session=boto3.Session(region_name=args.region)
    outputs={i['OutputKey']:i['OutputValue'] for i in session.client('cloudformation').describe_stacks(StackName=args.stack)['Stacks'][0]['Outputs']}
    digest=hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    item={'farm_id':outputs['FarmId'],'area_id':'BOUNDARIES','revision':digest,'geojson':json.loads(json.dumps(data),parse_float=Decimal)}
    params={'Item':item}
    if not args.replace: params['ConditionExpression']='attribute_not_exists(farm_id)'
    session.resource('dynamodb').Table(outputs['AreasTable']).put_item(**params)
    print(f'Imported {len(data["features"])} areas; revision={digest}')
if __name__=='__main__':main()
