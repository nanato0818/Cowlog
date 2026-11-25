"""Export only read/manage prototype credentials to a private Flutter config file."""
import argparse,json,os
from pathlib import Path
import boto3

def main():
    p=argparse.ArgumentParser();p.add_argument('--stack',required=True);p.add_argument('--output',required=True);p.add_argument('--region',default='ap-northeast-1')
    args=p.parse_args();target=Path(args.output).expanduser().resolve()
    if target.exists(): p.error('output exists; choose a new private file')
    session=boto3.Session(region_name=args.region)
    outputs={i['OutputKey']:i['OutputValue'] for i in session.client('cloudformation').describe_stacks(StackName=args.stack)['Stacks'][0]['Outputs']}
    secrets=session.client('secretsmanager')
    config={'COWLOG_DEMO':False,'COWLOG_API_URL':outputs['ApiUrl'],
            'COWLOG_READ_TOKEN':secrets.get_secret_value(SecretId=outputs['ReadSecretArn'])['SecretString'],
            'COWLOG_MANAGE_TOKEN':secrets.get_secret_value(SecretId=outputs['ManageSecretArn'])['SecretString']}
    target.parent.mkdir(parents=True,exist_ok=True)
    fd=os.open(target,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'w') as f: json.dump(config,f,indent=2);f.write('\n')
    except Exception:
        target.unlink(missing_ok=True);raise
    print(f'Saved private app configuration: {target}')
if __name__=='__main__': main()
