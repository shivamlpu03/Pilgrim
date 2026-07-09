import pandas as pd
import json
import base64
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
from time import sleep
from datetime import datetime
from google.cloud import bigquery
from google.oauth2 import service_account
import os
from airflow.models import Variable

def get_bq_client(credentials_info:str, project_id:str="phd-database-475011")->bigquery.Client:
    credentials_info = base64.b64decode(credentials_info).decode("utf-8")
    credentials_info = json.loads(credentials_info)
    
    SCOPES = ['https://www.googleapis.com/auth/bigquery',
          'https://www.googleapis.com/auth/drive.readonly']
    
    credentials = service_account.Credentials.from_service_account_info(credentials_info, scopes=SCOPES)
    client = bigquery.Client(credentials=credentials, project=project_id)
    return client
# --- GBQ Configuration ---
# For Airflow: credentials will come from Airflow Variables
# For local: credentials will come from environment variable or JSON file

# --- Brand-wise ASIN Configuration ---
BRAND_ASINS = {
    'PHD': [
        'B0F6YQC5LM', 'B0F6YP63KW', 'B0F6YWK6G9', 'B0F6YQLHZC', 'B0F6YWM114',
        'B0F6YQKSBX', 'B0F6YPD6MX', 'B0F6YPWYQT', 'B0FG83JXM4', 'B0FG877SY8',
        'B0FFMV81C9', 'B0FG35B8FP', 'B0FG37GBZ9', 'B0FFZ5FQZ7', 'B0FG8F5FD5',
        'B0FG841QCK', 'B0FG89C4ZS', 'B0FGDGJVXH', 'B0FG388CVF', 'B0FG39LH25',
        'B0FG8H58FM', 'B0FG8D8NYY', 'B0FH2CSL8W', 'B0FH2HZ6W2', 'B0FHDYM4B4',
        'B0FHBKWX6S', 'B0FJRXFN54', 'B0FJRWGMY8', 'B0FJS3T8P3', 'B0FJS4MT12',
        'B0FJSML3C3', 'B0FJSPV34R', 'B0FJTN9DCH', 'B0FJSWVLHS', 'B0FJTBNL16',
        'B0FJTJ642L', 'B0FL2LYQDN', 'B0FS2PHYWX', 'B0FS2BL729'
    ],
    'PILGRIM': [
        'B0D6G1JFZ2', 'B096Y23VJK', 'B0D5D945Q4', 'B0BM61RJKK', 'B09JVPQTY9',
        'B0F6D6X1QM', 'B0CRTQZ4HG', 'B0D5DBMKMC', 'B0D5D8S8G2', 'B0D5DBMVWG',
        'B0F6NTH43P', 'B0D5D8FMR2', 'B0CH8RMM21', 'B0FGDL8QCC', 'B0BM61RZ9Z',
        'B09TBBHMG6', 'B0836XVS63', 'B08WLSGJFC', 'B0F4DLD7D7', 'B0CV9PBHD2',
        'B0F6JLFPTZ', 'B0CH8SHN9Z', 'B0836YDMJ9', 'B096XYFJSQ', 'B096XYRM5X',
        'B0DJNVMZ1M', 'B0BM61BB79', 'B0DSJFYRZP', 'B0D5D9BF3Q', 'B0F6DDMPFL',
        'B0BS69XBML', 'B09TBJRXP3', 'B0CH8SRR1B', 'B0CJ9N5C8Y', 'B0F6D4Q1S5',
        'B0FGDLXVRW', 'B0CX22YL1V', 'B0DJNX7KMK', 'B0D5DBDX4B', 'B08RQJKF6D',
        'B0DSCD5RDM', 'B08RP7J2FY', 'B0B8D63GV6', 'B0836Y4TT2', 'B0F6NSQHKZ',
        'B08RP6NKLS', 'B09PHCH19D', 'B09JPF4VNX', 'B0CM8Z5WH2', 'B0CMDC27XJ'
    ]
}

# --- Configuration ---
BASE_URL = "https://www.amazon.in/dp/"
SELLER_ID_SELECTOR = 'sellerProfileTriggerId'
WAIT_TIME_BETWEEN_ASINS = 5  # seconds

def scrape_amazon_sellers(asin_list, brand_name):
    """
    Iterates through ASINs, scrapes seller info, and handles out-of-stock scenarios.
    """
    current_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    results = []

    print(f"\nStarting scrape for {brand_name} brand with {len(asin_list)} ASINs...")
    
    with sync_playwright() as p:
        browser = p.firefox.launch(headless=True)
        context = browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        )
        page = context.new_page()
        
        for i, asin in enumerate(asin_list):
            url = f"{BASE_URL}{asin}"
            scraped_seller_name = "N/A - Failed to Scrape"
            
            try:
                page.goto(url, wait_until='domcontentloaded', timeout=32000)
                
                try:
                    seller_element = page.wait_for_selector(
                        f'#{SELLER_ID_SELECTOR}',
                        timeout=30000
                    )
                    scraped_seller_name = seller_element.inner_text().strip()
                    print(f"[SUCCESS] {brand_name} - ASIN: {asin} -> Seller: {scraped_seller_name}")
                
                except PlaywrightTimeoutError:
                    try:
                        page.wait_for_selector('#outOfStock', timeout=30000)
                        price_element = page.locator(
                            '#outOfStock span.a-color-price.a-text-bold'
                        ).first
                        price_text = price_element.inner_text().strip()
                        scraped_seller_name = f"OUT_OF_STOCK_PRICE: {price_text}"
                        print(f"[FAILOVER SUCCESS] {brand_name} - ASIN: {asin} -> Status: {scraped_seller_name}")
                    
                    except PlaywrightTimeoutError:
                        print(f"[FINAL FAIL] {brand_name} - ASIN: {asin} -> Neither seller nor out-of-stock price found.")
                        scraped_seller_name = "N/A - Data Not Found"
            
            except Exception as e:
                print(f"[ERROR] {brand_name} - ASIN: {asin} -> Unexpected error: {str(e)}")
                scraped_seller_name = "N/A - Error Occurred"
            
            finally:
                results.append({
                    'ASIN': asin,
                    'Seller_Name': scraped_seller_name,
                    'Brand': brand_name,
                    'Scrape_Timestamp': current_timestamp,
                    'URL': url
                })
                
                if i < len(asin_list) - 1:
                    print(f"Waiting {WAIT_TIME_BETWEEN_ASINS}s...")
                    sleep(WAIT_TIME_BETWEEN_ASINS)
        
        context.close()
        browser.close()
    
    return pd.DataFrame(results)

def main():
    """
    Main execution function - can be called from Airflow or run locally
    """
    try:
        # Process PHD Brand 
        
        print("="*70)
        print("PROCESSING PHD BRAND")
        print("="*70)
        phd_df = scrape_amazon_sellers(BRAND_ASINS['PHD'], 'PHD')
        phd_df_filtered = phd_df[
            phd_df['Seller_Name'].str.lower() != "heavenly secrets pvt ltd.".lower()
        ] 
        
        credentials_info = Variable.get("GOOGLE_BIGQUERY_CREDENTIALS")
        bq_client  = get_bq_client(credentials_info) 
        job_config = bigquery.LoadJobConfig(write_disposition=bigquery.WriteDisposition.WRITE_APPEND) 
        job_config.schema_update_options = [bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION] 
        job_config.autodetect = True
        phd_df["ingestion_datetime"] = pd.to_datetime(datetime.utcnow()) 
        table_id_phd = 'phd-database-475011.Amazon_Web_Scraping.Amazon_Buy_Box_PHD'
        job = bq_client.load_table_from_dataframe(phd_df, table_id_phd, job_config=job_config) 
        job.result()
        # Save PHD data locally
        #phd_df.to_csv("PHD_All_ASIN_seller.csv", index=False)
        #phd_df_filtered.to_csv("PHD_amazon_seller_data_playwright.csv", index=False)
        
        print("\n" + "="*70)
        print("PHD Brand - Data saved locally and uploaded to BigQuery")
        print("="*70)
        
        # Process PILGRIM Brand
        print("\n" + "="*70)
        print("PROCESSING PILGRIM BRAND")
        print("="*70)
        pilgrim_df = scrape_amazon_sellers(BRAND_ASINS['PILGRIM'], 'PILGRIM')
        pilgrim_df_filtered = pilgrim_df[
            pilgrim_df['Seller_Name'].str.lower() != "heavenly secrets pvt ltd.".lower()
        ]
        pilgrim_df["ingestion_datetime"] = pd.to_datetime(datetime.utcnow())
        bq_client_shopi  = get_bq_client(credentials_info,"shopify-pubsub-project") 
        table_id = 'shopify-pubsub-project.Amazon_Market_Sizing.Amazon_Buy_Box'
        job = bq_client_shopi.load_table_from_dataframe(pilgrim_df, table_id, job_config=job_config) 
        job.result()
        # Save PILGRIM data locally
        #pilgrim_df.to_csv("PILGRIM_All_ASIN_seller.csv", index=False)
        #pilgrim_df_filtered.to_csv("PILGRIM_amazon_seller_data_playwright.csv", index=False)
        
        # Upload PILGRIM data to BigQuery
        
        print("\n" + "="*70)
        print("PILGRIM Brand - Data saved locally and uploaded to BigQuery")
        print("="*70)
        
        # Display summary
        print("\n" + "="*70)
        print("SCRAPING COMPLETE - SUMMARY")
        print("="*70)
        print(f"PHD Brand: {len(phd_df)} ASINs scraped, {len(phd_df_filtered)} after filtering")
        print(f"PILGRIM Brand: {len(pilgrim_df)} ASINs scraped, {len(pilgrim_df_filtered)} after filtering")
        print("="*70)
        
        return True
        
    except Exception as e:
        print(f"\nFATAL ERROR: Script failed to run. Error: {e}")
        raise


# --- Execution Block ---
if __name__ == "__main__":
    main()
