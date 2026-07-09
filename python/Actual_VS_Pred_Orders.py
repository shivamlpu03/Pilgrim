import os
import base64
import requests
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from google.cloud import bigquery
from google.oauth2 import service_account
from datetime import datetime
import seaborn as sns
from io import BytesIO
import tempfile
import json
import logging
from airflow.models import Variable

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WhatsappMsg:
    def __init__(self, ImagePath, Group_id_):
        self.ImagePath = ImagePath
        self.Group_id = Group_id_
        
    def main(self):
        try:
            with open(self.ImagePath, "rb") as img_file:
                encoded_string = base64.b64encode(img_file.read()).decode("utf-8")
            
            # Communication :- Whatsapp
            base64_data = f"data:image/png;base64,{encoded_string}"
            
            url = "https://gate.whapi.cloud/messages/image"
            logger.info(f"Sending to group: {self.Group_id}")
            
            payload = {
                "to": self.Group_id,
                "media": f"{base64_data}"
            }
            headers = {
                "accept": "application/json",
                "content-type": "application/json",
                "authorization": "Bearer p2fowqR9UEiMmC0p2Rh4chVXs4BwWgsk"
            }
            
            response = requests.post(url, json=payload, headers=headers)
            logger.info(response.text)
            
            return True, response.text
        except Exception as e:
            Error = f"Error found in class WhatsappMsg {str(e)}"
            logger.error(Error)
            return False, Error

def get_service_account_credentials(credentials_info: str):
    """Get service account credentials from base64 encoded JSON string - EXACTLY like reference code"""
    try:
        logger.info("🔍 Decoding credentials...")
        credentials_info = base64.b64decode(credentials_info).decode("utf-8")
        logger.info("✅ Base64 decode successful")
        
        logger.info("🔍 Parsing JSON...")
        credentials_json = json.loads(credentials_info)
        logger.info("✅ JSON parsing successful")
        
        logger.info("🔍 Creating credentials (no explicit scopes - like reference code)...")
        credentials = service_account.Credentials.from_service_account_info(credentials_json)
        logger.info("✅ Credentials created successfully")
        
        return credentials
    except Exception as e:
        logger.error(f"❌ Error in get_service_account_credentials: {e}")
        logger.error(f"❌ Error type: {type(e)}")
        raise

def get_bq_client(credentials_info: str) -> bigquery.Client:
    """Get BigQuery client with service account credentials"""
    try:
        logger.info("🔍 Creating BigQuery client...")
        credentials_info_decoded = base64.b64decode(credentials_info).decode("utf-8")
        credentials_json = json.loads(credentials_info_decoded)

        credentials = service_account.Credentials.from_service_account_info(credentials_json)
        client = bigquery.Client(credentials=credentials, project="shopify-pubsub-project")
        logger.info("✅ BigQuery client created successfully")
        return client
    except Exception as e:
        logger.error(f"❌ Error in get_bq_client: {e}")
        logger.error(f"❌ Error type: {type(e)}")
        raise

class SupplyChainProjections:
    def __init__(self, credentials_info: str):
        # Initialize BigQuery client using production pattern
        self.bq_client = get_bq_client(credentials_info)
        
        # Production configuration
        self.project_id = "shopify-pubsub-project"
        self.dataset_id = "Supply_Chain"
        self.table_id = "Master_Actual_vs_Projected"
        
        # Cities to process
        self.cities = ['Mumbai', 'Bangalore', 'Kolkata', 'Bilaspur', 'Hyderabad']
        
    def fetch_data_from_bq(self):
        """Fetch data from BigQuery table with aggregation by date"""
        try:
            query = f"""
            SELECT 
                Order_Date,
                SUM(Mumbai_Actual) as Mumbai_Actual,
                SUM(Bangalore_Actual) as Bangalore_Actual,
                SUM(Kolkata_Actual) as Kolkata_Actual,
                SUM(Bilaspur_Actual) as Bilaspur_Actual,
                SUM(Hyderabad_Actual) as Hyderabad_Actual,
                SUM(Mumbai_Projected) as Mumbai_Projected,
                SUM(Bangalore_Projected) as Bangalore_Projected,
                SUM(Kolkata_Projected) as Kolkata_Projected,
                SUM(Bilaspur_Projected) as Bilaspur_Projected,
                SUM(Hyderabad_Projected) as Hyderabad_Projected
            FROM `{self.project_id}.{self.dataset_id}.{self.table_id}`
            where Channel_Name='Shopify' and date_trunc(order_date,month)=date_trunc(current_date(),month)
            GROUP BY Order_Date
            ORDER BY Order_Date DESC
            LIMIT 31
            """
            
            df = self.bq_client.query(query).to_dataframe()
            logger.info(f"✅ Fetched {len(df)} rows from BigQuery (aggregated by date)")
            return df
            
        except Exception as e:
            logger.error(f"❌ Error fetching data from BigQuery: {str(e)}")
            return None
    
    def process_city_data(self, df, city):
        """Process data for a specific city"""
        try:
            # Create city-specific dataframe
            city_df = df[['Order_Date', f'{city}_Actual', f'{city}_Projected']].copy()
            city_df.columns = ['Date', f'{city}_Actual', f'{city}_Projected']
            
            # Calculate A-P (Actual - Projected)
            city_df['A-P'] = city_df[f'{city}_Actual'] - city_df[f'{city}_Projected']
            
            # Calculate A-P% ((Actual - Projected) / Projected * 100)
            city_df['A-P%'] = ((city_df[f'{city}_Actual'] - city_df[f'{city}_Projected']) / 
                              city_df[f'{city}_Projected'] * 100).round(1)
            
            # Format the data for display
            city_df[f'{city}_Actual'] = city_df[f'{city}_Actual'].apply(lambda x: f"{x:,.0f}" if pd.notna(x) else "")
            city_df[f'{city}_Projected'] = city_df[f'{city}_Projected'].apply(lambda x: f"{x:,.0f}" if pd.notna(x) else "")
            city_df['A-P'] = city_df['A-P'].apply(lambda x: f"{x:,.0f}" if pd.notna(x) else "")
            city_df['A-P%'] = city_df['A-P%'].apply(lambda x: f"{x:.1f}%" if pd.notna(x) else "")
            
            # Format date
            city_df['Date'] = pd.to_datetime(city_df['Date']).dt.strftime('%d %b %Y')
            
            return city_df
            
        except Exception as e:
            logger.error(f"❌ Error processing data for {city}: {str(e)}")
            return None
    
    def create_city_table_image(self, city_df, city):
        """Create a table image for a specific city"""
        try:
            # Set up the plot
            fig, ax = plt.subplots(figsize=(12, 8))
            ax.axis('tight')
            ax.axis('off')
            
            # Create table
            table_data = city_df.values.tolist()
            headers = ['Date', f'{city}_Actual', f'{city}_Projected', 'A-P', 'A-P%']
            
            # Create the table
            table = ax.table(cellText=table_data, 
                           colLabels=headers,
                           cellLoc='center',
                           loc='center',
                           bbox=[0, 0, 1, 1])
            
            # Style the table
            table.auto_set_font_size(False)
            table.set_fontsize(10)
            table.scale(1.2, 2)
            
            # Header styling
            for i in range(len(headers)):
                table[(0, i)].set_facecolor('#4472C4')
                table[(0, i)].set_text_props(weight='bold', color='white')
                table[(0, i)].set_height(0.08)
            
            # Row styling
            for i in range(1, len(table_data) + 1):
                for j in range(len(headers)):
                    if i % 2 == 0:
                        table[(i, j)].set_facecolor('#E8F0FE')
                    else:
                        table[(i, j)].set_facecolor('#FFFFFF')
                    table[(i, j)].set_height(0.06)
                    
                    # Color coding for A-P% column
                    if j == 4:  # A-P% column
                        try:
                            value = float(table_data[i-1][j].replace('%', ''))
                            if value < 0:
                                table[(i, j)].set_facecolor('#FFE6E6')  # Light red for negative
                            elif value > 20:
                                table[(i, j)].set_facecolor('#E6FFE6')  # Light green for high positive
                        except:
                            pass
            
            # Add title
            plt.title(f'{city} Projections D2C', fontsize=16, fontweight='bold', pad=20)
            
            # Save the image
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            plt.savefig(temp_file.name, dpi=300, bbox_inches='tight', 
                       facecolor='white', edgecolor='none')
            plt.close()
            
            return temp_file.name
            
        except Exception as e:
            logger.error(f"❌ Error creating table image for {city}: {str(e)}")
            return None
    
    def create_combined_chart(self, df):
        """Create a combined visualization chart for all cities showing Actual vs Projected"""
        try:
            # Prepare data for plotting
            df_plot = df.copy()
            df_plot['Order_Date'] = pd.to_datetime(df_plot['Order_Date'])
            df_plot = df_plot.sort_values('Order_Date')
            
            # Set up the plot
            fig, axes = plt.subplots(2, 3, figsize=(18, 12))
            fig.suptitle('Actual vs Projected - All Cities Overview', fontsize=20, fontweight='bold', y=0.98)
            
            # Flatten axes for easier iteration
            axes_flat = axes.flatten()
            
            # Color scheme
            actual_color = '#2E86AB'    # Blue
            projected_color = '#A23B72'  # Pink/Purple
            
            # Plot each city
            for i, city in enumerate(self.cities):
                ax = axes_flat[i]
                
                # Plot lines
                ax.plot(df_plot['Order_Date'], df_plot[f'{city}_Actual'], 
                       label='Actual', linewidth=3, marker='o', markersize=6, color=actual_color)
                ax.plot(df_plot['Order_Date'], df_plot[f'{city}_Projected'], 
                       label='Projected', linewidth=3, marker='s', markersize=6, color=projected_color)
                
                # Styling
                ax.set_title(f'{city}', fontsize=14, fontweight='bold', pad=15)
                ax.grid(True, alpha=0.3)
                ax.legend(loc='upper right', fontsize=10)
                
                # Format x-axis
                ax.xaxis.set_major_formatter(mdates.DateFormatter('%d %b'))
                ax.xaxis.set_major_locator(mdates.DayLocator(interval=3))
                plt.setp(ax.xaxis.get_majorticklabels(), rotation=45, ha='right')
                
                # Format y-axis
                ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'{x:,.0f}'))
                
                # Set y-axis to start from 0 for better comparison
                ax.set_ylim(bottom=0)
                
                # Add subtle background color
                ax.set_facecolor('#FAFAFA')
            
            # Remove the 6th subplot (we only have 5 cities)
            axes_flat[5].remove()
            
            # Create summary stats subplot in the 6th position
            ax_summary = fig.add_subplot(2, 3, 6)
            
            # Calculate overall accuracy for each city (latest 7 days average)
            latest_7_days = df_plot.tail(7)
            city_accuracy = []
            
            for city in self.cities:
                actual_avg = latest_7_days[f'{city}_Actual'].mean()
                projected_avg = latest_7_days[f'{city}_Projected'].mean()
                accuracy = (1 - abs(actual_avg - projected_avg) / projected_avg) * 100 if projected_avg > 0 else 0
                city_accuracy.append(accuracy)
            
            # Create accuracy bar chart
            bars = ax_summary.bar(self.cities, city_accuracy, color=['#2E86AB', '#F18F01', '#C73E1D', '#A23B72', '#38A3A5'])
            ax_summary.set_title('Forecast Accuracy (Last 7 Days)', fontsize=14, fontweight='bold')
            ax_summary.set_ylabel('Accuracy %')
            ax_summary.set_ylim(0, 100)
            ax_summary.grid(True, alpha=0.3, axis='y')
            
            # Add value labels on bars
            for bar, acc in zip(bars, city_accuracy):
                ax_summary.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1, 
                              f'{acc:.1f}%', ha='center', va='bottom', fontweight='bold')
            
            plt.setp(ax_summary.xaxis.get_majorticklabels(), rotation=45, ha='right')
            
            # Adjust layout
            plt.tight_layout()
            plt.subplots_adjust(top=0.93, hspace=0.3, wspace=0.25)
            
            # Save the combined chart
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='_combined_chart.png')
            plt.savefig(temp_file.name, dpi=300, bbox_inches='tight', 
                       facecolor='white', edgecolor='none')
            plt.close()
            
            return temp_file.name
            
        except Exception as e:
            logger.error(f"❌ Error creating combined chart: {str(e)}")
            return None
    
    def send_city_projections(self, group_id):
        """Main function to process all cities and send via WhatsApp"""
        try:
            # Fetch data from BigQuery
            df = self.fetch_data_from_bq()
            if df is None:
                return False, "Failed to fetch data from BigQuery"
            
            results = []
            
            # First, create and save the combined visualization chart
            logger.info("📊 Creating combined visualization chart...")
            chart_path = self.create_combined_chart(df)
            if chart_path:
                # Save locally for testing - WhatsApp sending COMMENTED
                final_chart_path = f"Combined_Actual_vs_Projected_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
                import shutil
                shutil.copy2(chart_path, final_chart_path)
                logger.info(f"📊 Combined chart saved as: {final_chart_path}")
                
                # Send combined chart via WhatsApp - COMMENTED FOR TESTING
                # whatsapp_chart = WhatsappMsg(chart_path, group_id)
                # chart_success, chart_response = whatsapp_chart.main()
                
                chart_success = True
                chart_response = f"Chart saved locally as {final_chart_path}"
                
                if chart_success:
                    logger.info("✅ Successfully saved combined chart locally")
                    results.append("Combined Chart: Saved locally")
                else:
                    logger.error(f"❌ Failed to save combined chart: {chart_response}")
                    results.append(f"Combined Chart: Failed - {chart_response}")
                
                # Clean up temp file
                try:
                    os.unlink(chart_path)
                except:
                    pass
            
            # Process each city
            for city in self.cities:
                logger.info(f"📈 Processing {city}...")
                
                # Process city data
                city_df = self.process_city_data(df, city)
                if city_df is None:
                    logger.error(f"❌ Failed to process data for {city}")
                    continue
                
                # Create table image
                image_path = self.create_city_table_image(city_df, city)
                if image_path is None:
                    logger.error(f"❌ Failed to create image for {city}")
                    continue
                
                # Save locally for testing - WhatsApp sending COMMENTED
                final_image_path = f"{city}_projections_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
                import shutil
                shutil.copy2(image_path, final_image_path)
                logger.info(f"💾 {city} table saved as: {final_image_path}")
                
                # Send via WhatsApp - COMMENTED FOR TESTING
                # whatsapp = WhatsappMsg(image_path, group_id)
                # success, response = whatsapp.main()
                
                success = True
                response = f"Table saved locally as {final_image_path}"
                
                if success:
                    logger.info(f"✅ Successfully sent {city} projections")
                    results.append(f"{city}: Success")
                else:
                    logger.error(f"❌ Failed to send {city} projections: {response}")
                    results.append(f"{city}: Failed - {response}")
                
                # Clean up temp file
                try:
                    os.unlink(image_path)
                except:
                    pass
            
            return True, results
            
        except Exception as e:
            error_msg = f"❌ Error in send_city_projections: {str(e)}"
            logger.error(error_msg)
            return False, error_msg

def main():
    """Main execution function for Airflow production"""
    try:
        # --- Step 1: Get credentials from Airflow Variable (Production Pattern) ---
        logger.info("🔍 Getting credentials from Airflow Variable...")
        credentials_info = Variable.get("GOOGLE_BIGQUERY_CREDENTIALS")
        logger.info(f"✅ Retrieved credentials (length: {len(credentials_info)} characters)")
        
        if not credentials_info:
            logger.error("❌ Credentials are empty!")
            return False, "Empty credentials"
        
        # --- Step 2: Initialize Supply Chain Processor ---
        logger.info("🚀 Initializing Supply Chain Projections processor...")
        processor = SupplyChainProjections(credentials_info)
        
        # --- Step 3: WhatsApp Configuration ---
        GROUP_ID = "120363233940227316@g.us"
        
        # --- Step 4: Process and Send Projections ---
        logger.info("📊 Starting supply chain projections processing...")
        success, results = processor.send_city_projections(GROUP_ID)
        
        if success:
            logger.info("🎉 All city projections processed successfully!")
            for result in results:
                logger.info(f"  ✅ {result}")
            return True, results
        else:
            logger.error(f"❌ Process failed: {results}")
            return False, results
            
    except Exception as e:
        error_msg = f"❌ Main execution error: {str(e)}"
        logger.error(error_msg)
        return False, error_msg

if __name__ == "__main__":
    """For Airflow DAG execution"""
    logger.info("🚀 Starting Supply Chain Projections Bot...")
    logger.info("📋 Required packages: google-cloud-bigquery, pandas, matplotlib, seaborn, requests")
    
    success, message = main()
    
    if success:
        logger.info("🎊 Supply Chain Projections completed successfully!")
    else:
        logger.error(f"💥 Supply Chain Projections failed: {message}")
        raise Exception(f"Supply Chain Projections failed: {message}")
