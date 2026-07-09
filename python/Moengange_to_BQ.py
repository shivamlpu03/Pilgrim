from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
import io
import pandas as pd
import re
import os
import json
import base64
from google.cloud import bigquery
from pandas_gbq import to_gbq
from airflow.models import Variable
import logging

# Set up loggingg
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_service_account_credentials(credentials_info: str):
    """Get service account credentials from base64 encoded JSON string - EXACTLY like reference code"""
    try:
        print("🔍 Decoding credentials...")
        credentials_info = base64.b64decode(credentials_info).decode("utf-8")
        print("✅ Base64 decode successful")
        
        print("🔍 Parsing JSON...")
        credentials_json = json.loads(credentials_info)
        print("✅ JSON parsing successful")
        
        print("🔍 Creating credentials (no explicit scopes - like reference code)...")
        credentials = service_account.Credentials.from_service_account_info(credentials_json)
        print("✅ Credentials created successfully")
        
        return credentials
    except Exception as e:
        print(f"❌ Error in get_service_account_credentials: {e}")
        print(f"❌ Error type: {type(e)}")
        raise

def get_bq_client(credentials_info: str) -> bigquery.Client:
    """Get BigQuery client with service account credentials"""
    try:
        print("🔍 Creating BigQuery client...")
        credentials_info = base64.b64decode(credentials_info).decode("utf-8")
        credentials_info = json.loads(credentials_info)

        credentials = service_account.Credentials.from_service_account_info(credentials_info)
        client = bigquery.Client(credentials=credentials, project="shopify-pubsub-project")
        print("✅ BigQuery client created successfully")
        return client
    except Exception as e:
        print(f"❌ Error in get_bq_client: {e}")
        print(f"❌ Error type: {type(e)}")
        raise

def clean_column_names(columns):
    """Helper: Clean column names"""
    return [
        re.sub(r'\s+', '_', col.lower().strip())
        .replace('-', '_')
        .replace('__', '_')
        .replace('/', '_')
        .replace(',', '_')
        .replace('(', '_')
        .replace(')', '_')
        for col in columns
    ]

def concat_and_clean(dfs):
    """Helper: Combine per channel and drop first column"""
    if dfs:
        df = pd.concat(dfs, ignore_index=True)
        if not df.empty and df.shape[1] > 1:
            df.drop(df.columns[0], axis=1, inplace=True)
        df = df.convert_dtypes()
        return df
    return pd.DataFrame()

def align_df_with_bq_schema(df, table_id, bq_client):
    """Helper function: align dataframe to existing BigQuery schema"""
    try:
        table = bq_client.get_table(table_id)
        bq_columns = [field.name for field in table.schema]
        
        print(f"🔍 BQ Schema columns for {table_id}: {bq_columns}")
        print(f"🔍 DataFrame columns: {list(df.columns)}")
        
        # Find missing columns in DataFrame
        missing_cols = list(set(bq_columns) - set(df.columns))
        if missing_cols:
            print(f"➕ Adding missing columns with null values: {missing_cols}")
            for col in missing_cols:
                df[col] = None  # Add missing columns with nulls
        
        # Find extra columns in DataFrame
        extra_cols = list(set(df.columns) - set(bq_columns))
        if extra_cols:
            print(f"➖ Removing extra columns: {extra_cols}")
        
        # Return DataFrame with columns in BQ schema order
        return df[bq_columns]
        
    except Exception as e:
        print(f"❌ Error aligning schema for {table_id}: {e}")
        print(f"🔄 Returning original DataFrame")
        return df

def safe_upload(df, table_name, label, bq_client, credentials_info):
    """Helper function: upload with schema-safe logic"""
    try:
        if df.empty:
            print(f"⚠️  {label} DataFrame is empty, skipping upload")
            return
            
        table_id = f"{GCP_PROJECT_ID}.{GCP_DATASET_ID}.{table_name}"
        print(f"📤 Preparing to upload {label} to {table_id}")
        
        # Cast all columns to string
        df = df.astype(str)
        
        # Align with BigQuery schema
        df = align_df_with_bq_schema(df, table_id, bq_client)
        
        print(f"📊 Final {label} DataFrame shape: {df.shape}")
        print(f"📊 Final {label} columns: {list(df.columns)}")
        
        # Set up credentials for pandas_gbq
        credentials_json = json.loads(base64.b64decode(credentials_info).decode("utf-8"))
        credentials = service_account.Credentials.from_service_account_info(credentials_json)
        
        # Upload to BigQuery
        to_gbq(df, f"{GCP_DATASET_ID}.{table_name}", 
               project_id=GCP_PROJECT_ID, 
               if_exists="append",
               credentials=credentials)
        
        logger.info(f"✅ Uploaded {label} to {GCP_DATASET_ID}.{table_name}")
        
    except Exception as e:
        logger.error(f"❌ Failed to upload {label} to {table_name}: {e}")
        print(f"❌ Upload error details: {e}")
        raise

def main():
    # --- Step 1: Get credentials from Airflow Variable ---
    try:
        print("🔍 Getting credentials from Airflow Variable...")
        credentials_info = Variable.get("GOOGLE_BIGQUERY_CREDENTIALS")
        print(f"✅ Retrieved credentials (length: {len(credentials_info)} characters)")
        
        if not credentials_info:
            print("❌ Credentials are empty!")
            return
            
    except Exception as e:
        print(f"❌ Failed to get Airflow Variable: {e}")
        return
    
    # Get service account credentials for Google Drive
    print("🔐 Setting up Google Drive credentials...")
    drive_credentials = get_service_account_credentials(credentials_info)
    service = build('drive', 'v3', credentials=drive_credentials)
    print("✅ Google Drive service initialized")
    
    # Get BigQuery client
    print("🔐 Setting up BigQuery client...")
    bq_client = get_bq_client(credentials_info)
    print("✅ BigQuery client initialized")
    
    # --- Step 2: Direct configuration values ---
    global GCP_PROJECT_ID, GCP_DATASET_ID, BQ_TABLE_SMS, BQ_TABLE_WHATSAPP, BQ_TABLE_PUSH, BQ_TABLE_EMAIL
    
    GCP_PROJECT_ID = "shopify-pubsub-project"
    GCP_DATASET_ID = "Customer_Retention"
    BQ_TABLE_SMS = "SMS"
    BQ_TABLE_WHATSAPP = "WHATSAPP"
    BQ_TABLE_PUSH = "PUSH"
    BQ_TABLE_EMAIL = "EMAIL"
    
    # --- Step 3: Folder ID and debugging ---
    folder_id = '1QjlRCHBv2YlN6t3LARMNQFf-VOpKGL5S'
    print(f"🔗 Using folder ID: {folder_id}")
    
    # Test basic Drive API connection
    try:
        about = service.about().get(fields="user").execute()
        service_account_email = about.get('user', {}).get('emailAddress', 'Unknown')
        print(f"✅ Connected to Google Drive as: {service_account_email}")
        print(f"🔑 Make sure this email has access to the folder: {folder_id}")
        print(f"📧 Service account email to share folder with: {service_account_email}")
    except Exception as e:
        print(f"❌ Failed to connect to Google Drive: {e}")
        return

    # --- Step 4: Define patterns ---
    patterns = ['email', 'sms', 'push', 'wtsp', 'whatsapp']

    # --- Step 5: List matching files in the folder ---
    print(f"🔍 Searching for files in folder: {folder_id}")
    
    results = service.files().list(
        q=f"'{folder_id}' in parents and mimeType='text/csv'",
        fields="files(id, name)").execute()

    files = results.get('files', [])
    print(f"📁 Found {len(files)} CSV files in folder:")
    for file in files:
        print(f"  - {file['name']}")
    
    filtered_files = [f for f in files if any(p in f['name'].lower() for p in patterns)]
    print(f"🎯 Found {len(filtered_files)} files matching patterns {patterns}:")
    for file in filtered_files:
        print(f"  - {file['name']}")

    if not filtered_files:
        print("❌ No matching files found.")
        print("🔍 Let's try to list ALL files in the folder to debug:")
        
        # Try to list all files (not just CSV)
        all_results = service.files().list(
            q=f"'{folder_id}' in parents",
            fields="files(id, name, mimeType)").execute()
        
        all_files = all_results.get('files', [])
        print(f"📂 All files in folder ({len(all_files)} total):")
        for file in all_files:
            print(f"  - {file['name']} (Type: {file['mimeType']})")
        
        return

    # --- Step 6: Download and organize files by type ---
    dfs_email, dfs_sms, dfs_push, dfs_wtsp = [], [], [], []

    for file in filtered_files:
        file_id = file['id']
        file_name = file['name'].lower()
        print(f"\n📥 Downloading: {file_name}")

        request = service.files().get_media(fileId=file_id)
        fh = io.BytesIO()
        downloader = MediaIoBaseDownload(fh, request)
        done = False
        while not done:
            status, done = downloader.next_chunk()
            print(f"  ➤ Download progress: {int(status.progress() * 100)}%")

        fh.seek(0)

        try:
            df = pd.read_csv(fh)
            df.columns = clean_column_names(df.columns)
        except Exception as e:
            print(f"❌ Failed to read {file_name}: {e}")
            continue

        # --- Cleaning ---
        df['pg_extracted_at'] = pd.Timestamp.now()

        # Replace "exclude" variations with 0
        df.replace(
            to_replace=r'excl(ude)?d?\s?\w*|exl(ude)?\s?\w*',
            value=0,
            regex=True,
            inplace=True
        )

        # Replace blank/whitespace-only cells with 0
        df.replace(r'^\s*$', 0, regex=True, inplace=True)

        # Replace NaNs with 0
        df.fillna(0, inplace=True)

        # Append to appropriate list
        if 'email' in file_name:
            dfs_email.append(df)
        elif 'sms' in file_name:
            dfs_sms.append(df)
        elif 'push' in file_name:
            dfs_push.append(df)
        elif 'wtsp' in file_name or 'whatsapp' in file_name:
            dfs_wtsp.append(df)

    # --- Step 7: Combine per channel and drop first column ---
    df_email = concat_and_clean(dfs_email)
    df_sms = concat_and_clean(dfs_sms)
    df_push = concat_and_clean(dfs_push)
    df_wtsp = concat_and_clean(dfs_wtsp)

    # --- Step 8: Upload to BigQuery with schema alignment ---
    print("\n🚀 Starting BigQuery uploads with schema alignment...")

    # Upload each DataFrame using the safe_upload function
    safe_upload(df_sms, BQ_TABLE_SMS, "df_sms", bq_client, credentials_info)
    safe_upload(df_wtsp, BQ_TABLE_WHATSAPP, "df_wtsp", bq_client, credentials_info)
    safe_upload(df_push, BQ_TABLE_PUSH, "df_push", bq_client, credentials_info)
    safe_upload(df_email, BQ_TABLE_EMAIL, "df_email", bq_client, credentials_info)

    print("✅ All data processing and upload completed successfully!")

if __name__ == "__main__":
    main()
