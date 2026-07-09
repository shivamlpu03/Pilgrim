import smtplib
import sys
import pandas as pd 
from google.oauth2 import service_account
from google.cloud import bigquery
import pandas_gbq as pgbq
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email import encoders
from airflow.models import Variable
from datetime import datetime, timedelta, date
import os 
import base64 
import json

def get_bq_client(credentials_info: str, project_id: str = "phd-database-475011") -> bigquery.Client:
    """
    Create BigQuery client with credentials for specified project
    """
    credentials_info = base64.b64decode(credentials_info).decode("utf-8")
    credentials_info = json.loads(credentials_info)
    
    SCOPES = [
        'https://www.googleapis.com/auth/bigquery',
        'https://www.googleapis.com/auth/drive.readonly'
    ]
    
    credentials = service_account.Credentials.from_service_account_info(
        credentials_info, 
        scopes=SCOPES
    )
    client = bigquery.Client(credentials=credentials, project=project_id)
    return client 


def read_from_gbq(bq_client, query: str):
    """
    Execute query and return dataframe
    """
    df = bq_client.query(query).to_dataframe() 
    return df


def send_amazon_phd_mailer():
    """
    Main function to fetch data from both datasets and send emails
    """
    # Get credentials
    credentials_info = Variable.get("GOOGLE_BIGQUERY_CREDENTIALS") 
    
    # Email configuration
    SENDER_EMAIL = "cloud@discoverpilgrim.com"
    EMAIL_PASSWORD = Variable.get("EMAIL_PASSWORD")
    CC_EMAIL = "bi@discoverpilgrim.com"
    
    # PHD Mailer - Project 1
    PHD_RECIPIENT = "satyesh@discoverpilgrim.com,aishwarya.suvarna@discoverpilgrim.com"
    phd_project_id = "phd-database-475011"
    phd_query = "SELECT * FROM `phd-database-475011.Amazon_Web_Scraping.PHD_Mailer`"
    
    # AMZ Mailer - Project 2
    AMZ_RECIPIENT = "marketplace2@discoverpilgrim.com,swati.sachdeva@discoverpilgrim.com,amrutha.renganathan@discoverpilgrim.com"
    amz_project_id = "shopify-pubsub-project"
    amz_query = "SELECT * FROM `shopify-pubsub-project.Amazon_Market_Sizing.AMZ_Mailer`"
    
    try:
        # Fetch PHD data
        print("Fetching PHD Mailer data...")
        phd_client = get_bq_client(credentials_info, phd_project_id)
        df_phd = read_from_gbq(phd_client, phd_query)
        
        # Fetch AMZ data
        print("Fetching AMZ Mailer data...")
        amz_client = get_bq_client(credentials_info, amz_project_id)
        df_amz = read_from_gbq(amz_client, amz_query)
        
        # Send PHD Email
        handle_phd_email(df_phd, PHD_RECIPIENT, CC_EMAIL, SENDER_EMAIL, EMAIL_PASSWORD)
        
        # Send AMZ Email
        handle_amz_email(df_amz, AMZ_RECIPIENT, CC_EMAIL, SENDER_EMAIL, EMAIL_PASSWORD)
        
        print("All emails sent successfully!")
        
    except Exception as e:
        print(f"Error in send_amazon_phd_mailer: {e}")
        raise


def handle_phd_email(dataframe, recipient, cc_email, sender_email, sender_password):
    """
    Handle PHD mailer email
    """
    # Get max date from the dataframe (even if empty)
    max_date = ""
    date_columns = ['date', 'Date', 'DATE', 'created_date', 'report_date', 'Report_Date']
    
    if not dataframe.empty:
        for col in date_columns:
            if col in dataframe.columns:
                max_date = pd.to_datetime(dataframe[col]).max().strftime('%Y-%m-%d')
                break
        
        # If no date column found, check all columns for datetime type
        if not max_date:
            for col in dataframe.columns:
                if pd.api.types.is_datetime64_any_dtype(dataframe[col]):
                    max_date = pd.to_datetime(dataframe[col]).max().strftime('%Y-%m-%d')
                    break
    
    # If still no date found, use today's date
    if not max_date:
        max_date = date.today().strftime('%Y-%m-%d')
    
    date_str = f" for {max_date}"
    subject = f"PHD Amazon BuyBox Pilgrim Products{date_str}"
    
    if not dataframe.empty:
        
        # Convert dataframe to HTML table
        html_table = dataframe.to_html(index=False, border=1, justify='center', classes='table')
        
        # Add CSS styling to the table
        body = f"""
        <html>
        <head>
            <style>
                .table {{
                    border-collapse: collapse;
                    width: 100%;
                    font-family: Arial, sans-serif;
                    font-size: 12px;
                }}
                .table th {{
                    background-color: #4CAF50;
                    color: white;
                    padding: 8px;
                    text-align: left;
                }}
                .table td {{
                    border: 1px solid #ddd;
                    padding: 8px;
                }}
                .table tr:nth-child(even) {{
                    background-color: #f2f2f2;
                }}
            </style>
        </head>
        <body>
            <p>Hi Satyesh,</p>
            <p>Please find the PHD Amazon BuyBox Pilgrim Products below{date_str}.</p>
            <br>
            {html_table}
            <br>
            <p>Regards,<br>BI Team</p>
        </body>
        </html>
        """
        
        send_email(sender_email, sender_password, recipient, cc_email, subject, body)
        print(f"PHD Mail sent to {recipient} with HTML table.")
    else:
        body = f"""<html><body>
        <p>Hi Satyesh,</p>
        <p>No products found on {max_date}.</p>
        <br>
        <p>Regards,<br>BI Team</p>
        </body></html>"""
        send_email(sender_email, sender_password, recipient, cc_email, subject, body)
        print(f"PHD Mail sent to {recipient} - No data found for {max_date}.")


def handle_amz_email(dataframe, recipient, cc_email, sender_email, sender_password):
    """
    Handle AMZ mailer email
    """
    if not dataframe.empty:
        # Get max date from the dataframe
        max_date = ""
        date_columns = ['date', 'Date', 'DATE', 'created_date', 'report_date', 'Report_Date']
        for col in date_columns:
            if col in dataframe.columns:
                max_date = pd.to_datetime(dataframe[col]).max().strftime('%Y-%m-%d')
                break
        
        # If no date column found, check all columns for datetime type
        if not max_date:
            for col in dataframe.columns:
                if pd.api.types.is_datetime64_any_dtype(dataframe[col]):
                    max_date = pd.to_datetime(dataframe[col]).max().strftime('%Y-%m-%d')
                    break
        
        date_str = f" for {max_date}" if max_date else ""
        subject = f"Amazon BuyBox Pilgrim Products{date_str}"
        
        # Convert dataframe to HTML table
        html_table = dataframe.to_html(index=False, border=1, justify='center', classes='table')
        
        # Add CSS styling to the table
        body = f"""
        <html>
        <head>
            <style>
                .table {{
                    border-collapse: collapse;
                    width: 100%;
                    font-family: Arial, sans-serif;
                    font-size: 12px;
                }}
                .table th {{
                    background-color: #4CAF50;
                    color: white;
                    padding: 8px;
                    text-align: left;
                }}
                .table td {{
                    border: 1px solid #ddd;
                    padding: 8px;
                }}
                .table tr:nth-child(even) {{
                    background-color: #f2f2f2;
                }}
            </style>
        </head>
        <body>
            <p>Hi Team,</p>
            <p>Please find the Amazon BuyBox Pilgrim Products below{date_str}.</p>
            <br>
            {html_table}
            <br>
            <p>Regards,<br>BI Team</p>
        </body>
        </html>
        """
        
        send_email(sender_email, sender_password, recipient, cc_email, subject, body)
        print(f"AMZ Mail sent to {recipient} with HTML table.")
    else:
        subject = "Amazon BuyBox Pilgrim Products"
        body = """<html><body>
        <p>Hi Team,</p>
        <p>No data available in Amazon BuyBox report for today.</p>
        <br>
        <p>Regards,<br>BI Team</p>
        </body></html>"""
        send_email(sender_email, sender_password, recipient, cc_email, subject, body)
        print(f"AMZ Mail sent to {recipient} - No data found.")


def send_email(sender_email, sender_password, recipient_email, cc_email, subject, body, attachment_paths=None):
    """
    Send email with optional attachments
    """
    try:
        if not body.strip():
            raise ValueError("Email body cannot be empty")
    
        msg = MIMEMultipart()
        msg['From'] = sender_email
        msg['To'] = recipient_email 
        if cc_email:
            msg['Cc'] = cc_email
        msg['Subject'] = subject 
        msg.attach(MIMEText(body, 'html'))

        if attachment_paths:
            for file_path in attachment_paths:
                with open(file_path, "rb") as file:
                    attachment = MIMEBase("application", "octet-stream")
                    attachment.set_payload(file.read())
                    encoders.encode_base64(attachment)
                    attachment.add_header(
                        "Content-Disposition", 
                        f"attachment; filename={os.path.basename(file_path)}"
                    )
                    msg.attach(attachment)

        server = smtplib.SMTP('smtp.gmail.com', 587)
        server.starttls()
        server.login(sender_email, sender_password)
        
        # Send to recipient and CC
        all_recipients = [recipient_email]
        if cc_email:
            all_recipients.append(cc_email)
        
        server.sendmail(sender_email, all_recipients, msg.as_string())
        server.quit()
        return True

    except Exception as e:
        print(f"Error sending email: {e}")
        return False


if __name__ == "__main__":
    send_amazon_phd_mailer()
