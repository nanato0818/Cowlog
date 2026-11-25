import os,sys,json,unittest
from pathlib import Path
from datetime import datetime,timedelta,timezone
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'apps/api'))
import boto3
from moto import mock_aws
from aws_backend import Store,handler,Conflict,TooLarge,iso

NOW=datetime(2026,11,9,3,tzinfo=timezone.utc)

class BackendTests(unittest.TestCase):
    def setUp(self):
        self.env=patch.dict(os.environ,{'AWS_DEFAULT_REGION':'ap-northeast-1','AWS_ACCESS_KEY_ID':'testing','AWS_SECRET_ACCESS_KEY':'testing','REGISTRY_TABLE':'registry','MEASUREMENTS_TABLE':'measurements','AREAS_TABLE':'areas','FARM_ID':'daigo','COWLOG_READ_TOKEN':'read-test','COWLOG_MANAGE_TOKEN':'manage-test','COWLOG_INGEST_TOKEN':'ingest-test'})
        self.env.start();self.mock=mock_aws();self.mock.start()
        self.db=boto3.resource('dynamodb')
        for name,pk,sk in [('registry','pk','sk'),('measurements','device_id','record_key'),('areas','farm_id','area_id')]:
            self.db.create_table(TableName=name,KeySchema=[{'AttributeName':pk,'KeyType':'HASH'},{'AttributeName':sk,'KeyType':'RANGE'}],AttributeDefinitions=[{'AttributeName':pk,'AttributeType':'S'},{'AttributeName':sk,'AttributeType':'S'}],BillingMode='PAY_PER_REQUEST')
        self.store=Store(self.db)
    def tearDown(self): self.mock.stop();self.env.stop()
    def record(self,seq=1,at=NOW,**updates):
        return dict(device_id='collar-A',stream_id=10,seq=seq,measured_at=iso(at),latitude=33.4992,longitude=132.6740,activity_seconds=60,coverage_seconds=300,interval_seconds=300,**updates)
    def call(self,method,path,role='read',body=None,query=None,**extra):
        event={'rawPath':path,'requestContext':{'http':{'method':method}},'headers':{'Authorization':'Bearer '+role+'-test'},'queryStringParameters':query or {}}
        if body is not None: event['body']=json.dumps(body)
        event.update(extra)
        response=handler(event,None,self.store)
        return response['statusCode'],json.loads(response['body'])
    def test_registration_number_style_and_atomic_conflicts(self):
        self.store.create_collar('collar-A','0007','brown')
        self.store.create_collar('collar-B','0008')
        with self.assertRaises(Conflict): self.store.create_collar('collar-C','0007')
        self.assertIsNone(self.store.get('collar-C'))
        with self.assertRaises(Conflict): self.store.set_number('collar-A',{'number':'0008','expected_number':'0007'})
        self.assertEqual(self.store.get('collar-A')['number'],'0007')
        result=self.store.set_number('collar-A',{'number':'0020','expected_number':'0007','cow_style':'holstein','expected_style':'brown'})
        self.assertEqual(result['cow_style'],'holstein')
        self.assertEqual(self.store.set_number('collar-A',{'number':'0020','expected_number':'0007','cow_style':'holstein','expected_style':'brown'}),result)
        self.store.create_collar('collar-C','0007') # old number was released atomically
        with self.assertRaises(Conflict): self.store.set_number('collar-A',{'number':'0020','expected_number':'0020','cow_style':'brown','expected_style':'unknown'})
    def test_ingest_dedup_late_arrivals_and_identity_collision(self):
        self.store.create_collar('collar-A','0007')
        self.assertEqual(self.store.ingest([self.record()],NOW),{'accepted':1,'duplicates':0})
        self.assertEqual(self.store.ingest([self.record()],NOW),{'accepted':0,'duplicates':1})
        old=self.record(2,NOW-timedelta(hours=1))
        old['latitude']=33.5
        self.store.ingest([old],NOW)
        self.assertEqual(self.store.get('collar-A')['fix_data']['latitude'],33.4992)
        changed=self.record();changed['latitude']=33.6
        with self.assertRaises(Conflict): self.store.ingest([changed],NOW)
        h=self.store.history('collar-A','2026-11-09')
        self.assertEqual(len(h['measurements']),2)
        self.assertEqual(h['measurements'][0]['seq'],2)
    def test_retry_repairs_latest_cache_after_a_partial_failure(self):
        self.store.create_collar('collar-A','0007')
        original=self.store._latest
        with patch.object(self.store,'_latest',side_effect=RuntimeError('temporary')):
            with self.assertRaises(RuntimeError): self.store.ingest([self.record()],NOW)
        self.assertNotIn('latest_at',self.store.get('collar-A'))
        self.assertEqual(self.store.ingest([self.record()],NOW)['duplicates'],1)
        self.assertEqual(self.store.get('collar-A')['latest_at'],iso(NOW))
    def test_japanese_date_boundary_and_pagination(self):
        self.store.create_collar('collar-A','0007')
        before=NOW.replace(hour=15)-timedelta(seconds=1) # 23:59:59 JST Nov 9
        after=before+timedelta(seconds=1)
        self.store.ingest([self.record(1,before),self.record(2,after)],after)
        self.assertEqual([r['seq'] for r in self.store.history('collar-A','2026-11-09')['measurements']],[1])
        self.assertEqual([r['seq'] for r in self.store.history('collar-A','2026-11-10')['measurements']],[2])
        query=self.store.measurements.query
        with patch.object(self.store.measurements,'query',side_effect=lambda **kw:query(**kw,Limit=1)):
            self.assertEqual(len(self.store.rows('collar-A',NOW,NOW+timedelta(days=1))),2)
    def test_http_authorization_validation_and_real_app_response_shape(self):
        self.assertEqual(self.call('POST','/v1/collars',body={'device_id':'collar-A','number':'0007'})[0],401)
        self.assertEqual(self.call('POST','/v1/collars','manage',{'device_id':'collar-A','number':'0007','cow_style':'brown'})[0],201)
        self.assertEqual(self.call('POST','/v1/measurements','manage',{'records':[self.record()]})[0],401)
        with patch('aws_backend.utcnow',return_value=NOW):
            self.assertEqual(self.call('POST','/v1/measurements','ingest',{'records':[self.record()]})[0],200)
            status,body=self.call('GET','/v1/dashboard')
        self.assertEqual(status,200)
        self.assertEqual(body['cows'][0]['number'],'0007')
        self.assertEqual(body['cows'][0]['cow_style'],'brown')
        self.assertEqual(body['cows'][0]['status'],'insufficient')
        self.assertEqual(body['cows'][0]['latest_position']['latitude'],33.4992)
        self.assertEqual(self.call('GET','/v1/cows/collar-A/history',query={'date':'bad'})[0],400)
        self.assertEqual(self.call('GET','/v1/cows/unknown/history',query={'date':'2026-11-09'})[0],404)
        self.assertEqual(self.call('POST','/v1/measurements','ingest',{'records':[{'bad':True}]})[0],400)
        self.assertEqual(self.call('POST','/v1/collars','manage',body='not-an-object')[0],400)
    def test_unregistered_device_and_invalid_batch_are_not_partly_saved(self):
        with self.assertRaises(LookupError): self.store.ingest([self.record()],NOW)
        self.store.create_collar('collar-A','0007')
        with self.assertRaises(ValueError): self.store.ingest([self.record(),{'invalid':1}],NOW)
        self.assertEqual(self.store.history('collar-A','2026-11-09')['measurements'],[])
    def test_secrets_fail_closed_and_errors_do_not_expose_trace(self):
        with patch.dict(os.environ,{'COWLOG_MANAGE_TOKEN':'read-test'}):
            self.assertEqual(self.call('GET','/v1/collars')[0],503)
        with patch.dict(os.environ,{'COWLOG_READ_TOKEN':''}):
            self.assertEqual(self.call('GET','/v1/collars')[0],401)
        with patch.object(self.store,'list',side_effect=RuntimeError('internal database detail')):
            with self.assertLogs('aws_backend',level='ERROR'):
                status,body=self.call('GET','/v1/collars')
        self.assertEqual(status,503)
        self.assertNotIn('internal database detail',json.dumps(body))
    def test_registration_retry_and_capacity_guard(self):
        self.assertTrue(self.store.create_collar('collar-A','0007')['created'])
        self.assertFalse(self.store.create_collar('collar-A','0007')['created'])
        self.store.registry.update_item(Key={'pk':self.store.pk,'sk':'LIMITS'},UpdateExpression='SET collar_count=:n',ExpressionAttributeValues={':n':100})
        with self.assertRaises(TooLarge): self.store.create_collar('collar-B','0008')
        self.assertIsNone(self.store.get('collar-B'))

    def test_area_document_and_stage_prefix(self):
        geo={'type':'FeatureCollection','features':[]}
        self.db.Table('areas').put_item(Item={'farm_id':'daigo','area_id':'BOUNDARIES','geojson':geo})
        self.assertEqual(self.call('GET','/v1/farm/areas'),(200,geo))
        status,_=self.call('GET','/prod/v1/collars',requestContext={'stage':'prod','http':{'method':'GET'}})
        self.assertEqual(status,200)
if __name__=='__main__': unittest.main()
