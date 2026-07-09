import pandas as pd
import json
import base64
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeoutError
from time import sleep
from datetime import datetime
from google.cloud import bigquery
from google.oauth2 import service_account
from airflow.models import Variable

def get_bq_client(credentials_info: str, project_id: str = "phd-database-475011") -> bigquery.Client:
    """
    Creates BigQuery client from base64-encoded credentials
    """
    credentials_info = base64.b64decode(credentials_info).decode("utf-8")
    credentials_info = json.loads(credentials_info)
    
    SCOPES = [
        'https://www.googleapis.com/auth/bigquery',
        'https://www.googleapis.com/auth/drive.readonly'
    ]
    
    credentials = service_account.Credentials.from_service_account_info(
        credentials_info, scopes=SCOPES
    )
    client = bigquery.Client(credentials=credentials, project=project_id)
    return client

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
    ]
}

# --- Configuration ---
BASE_URL = "https://www.amazon.in/dp/"
SELLER_ID_SELECTOR = 'sellerProfileTriggerId'
WAIT_TIME_BETWEEN_ASINS = 5  # seconds


def scrape_single_asin(page, asin, brand_name, current_timestamp):
    """
    Scrapes a single ASIN and returns the result dictionary
    """
    url = f"{BASE_URL}{asin}"
    scraped_seller_name = "N/A - Failed to Scrape"
    
    try:
        page.goto(url, wait_until='domcontentloaded', timeout=32000)
        
        try:
            seller_element = page.wait_for_selector(
                f'#{SELLER_ID_SELECTOR}',
                timeout=10000
            )
            scraped_seller_name = seller_element.inner_text().strip()
            print(f"[SUCCESS] {brand_name} - ASIN: {asin} -> Seller: {scraped_seller_name}")
        
        except PlaywrightTimeoutError:
            try:
                page.wait_for_selector('#outOfStock', timeout=10000)
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
    
    return {
        'ASIN': asin,
        'Seller_Name': scraped_seller_name,
        'Brand': brand_name,
        'Scrape_Timestamp': current_timestamp,
        'URL': url
    }


def scrape_amazon_sellers(asin_list, brand_name):
    """
    Iterates through ASINs, scrapes seller info, and handles out-of-stock scenarios.
    Retries failed ASINs once before giving up.
    """
    current_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    results = []
    failed_asins = []

    print(f"\nStarting scrape for {brand_name} brand with {len(asin_list)} ASINs...")
    
    with sync_playwright() as p:
        browser = p.firefox.launch(headless=True)
        context = browser.new_context(
            viewport={'width': 1920, 'height': 1080},
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        )
        page = context.new_page()
        
        # First pass - scrape all ASINs
        print("\n--- FIRST PASS ---")
        for i, asin in enumerate(asin_list):
            result = scrape_single_asin(page, asin, brand_name, current_timestamp)
            results.append(result)
            
            # Track failed ASINs for retry
            if result['Seller_Name'] in ['N/A - Failed to Scrape', 'N/A - Data Not Found', 'N/A - Error Occurred']:
                failed_asins.append(asin)
            
            if i < len(asin_list) - 1:
                print(f"Waiting {WAIT_TIME_BETWEEN_ASINS}s...")
                sleep(WAIT_TIME_BETWEEN_ASINS)
        
        # Second pass - retry failed ASINs only once
        if failed_asins:
            print(f"\n--- RETRY PASS ({len(failed_asins)} failed ASINs) ---")
            retry_results = {}
            
            for i, asin in enumerate(failed_asins):
                print(f"[RETRY] Attempting ASIN: {asin}")
                retry_result = scrape_single_asin(page, asin, brand_name, current_timestamp)
                retry_results[asin] = retry_result
                
                if i < len(failed_asins) - 1:
                    print(f"Waiting {WAIT_TIME_BETWEEN_ASINS}s...")
                    sleep(WAIT_TIME_BETWEEN_ASINS)
            
            # Update results with retry data
            for idx, result in enumerate(results):
                if result['ASIN'] in retry_results:
                    results[idx] = retry_results[result['ASIN']]
                    print(f"[UPDATED] ASIN: {result['ASIN']} with retry result")
        
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
        
        # Add ingestion timestamp
        phd_df["ingestion_datetime"] = pd.to_datetime(datetime.utcnow())
        
        # Get credentials from Airflow Variable
        credentials_info = Variable.get("GOOGLE_BIGQUERY_CREDENTIALS")
        bq_client = get_bq_client(credentials_info)
        
        # Configure BigQuery load job
        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            schema_update_options=[bigquery.SchemaUpdateOption.ALLOW_FIELD_ADDITION],
            autodetect=True
        )
        
        # Upload to BigQuery
        table_id_phd = 'phd-database-475011.Amazon_Web_Scraping.Amazon_Buy_Box_PHD'
        job = bq_client.load_table_from_dataframe(phd_df, table_id_phd, job_config=job_config)
        job.result()  # Wait for job to complete
        
        # Display results
        print("\n" + "="*70)
        print("LOCAL RESULTS")
        print("="*70)
        print(f"\nTotal ASINs scraped: {len(phd_df)}")
        
        # Count success vs failures
        success_count = len(phd_df[~phd_df['Seller_Name'].str.contains('N/A -', na=False)])
        failed_count = len(phd_df[phd_df['Seller_Name'].str.contains('N/A -', na=False)])
        
        print(f"Successful scrapes: {success_count}")
        print(f"Failed scrapes: {failed_count}")
        
        print("\n--- ALL SCRAPED DATA ---")
        print(phd_df.to_string(index=False))
        
        print("\n" + "="*70)
        print("PHD Brand - Data uploaded to BigQuery")
        print("="*70)
        print(f"Table: {table_id_phd}")
        print(f"Rows uploaded: {len(phd_df)}")
        print("="*70)
        
        return True
        
    except Exception as e:
        print(f"\nFATAL ERROR: Script failed to run. Error: {e}")
        raise


# --- Execution Block ---
if __name__ == "__main__":
    main()
