#!/usr/bin/env python3
"""
DropDial License Webhook Server (Self-Hosted / Razorpay Integration)
===================================================================
Automatically issues and emails cryptographically signed license keys
upon successful Razorpay payment.

Features:
- Validates Razorpay webhook cryptographic signatures (HMAC SHA-256)
- Automatically issues ECDSA P-256 license keys
- Sends professional HTML delivery emails via SMTP (Gmail, Zoho, SendGrid, SES, etc.)
- Records purchases to a persistent CSV database
- Zero complex dependencies — runs using standard library or Flask

Usage:
    python app.py
"""

import csv
import hashlib
import hmac
import http.server
import json
import os
import smtplib
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from urllib.parse import parse_qs, urlparse

# Add parent directory to path to import keygen
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
import keygen

# Configuration via environment variables
PORT = int(os.environ.get("PORT", 8080))
WEBHOOK_SECRET = os.environ.get("RAZORPAY_WEBHOOK_SECRET", "change_me_to_your_webhook_secret")
ADMIN_KEY = os.environ.get("ADMIN_KEY", "admin_secret_key_123")

# Email / SMTP Configuration
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", 587))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASS = os.environ.get("SMTP_PASS", "")
FROM_EMAIL = os.environ.get("FROM_EMAIL", "support@dropdial.com")
FROM_NAME = os.environ.get("FROM_NAME", "DropDial Support")

DB_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "licenses.csv")


def record_license(email: str, name: str, key: str, payment_id: str, amount: str):
    """Save customer license to CSV database."""
    file_exists = os.path.exists(DB_FILE)
    with open(DB_FILE, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(["Timestamp", "Email", "Name", "LicenseKey", "PaymentId", "Amount"])
        writer.writerow([datetime.utcnow().isoformat(), email, name, key, payment_id, amount])


def send_license_email(to_email: str, name: str, license_key: str):
    """Send branded, professional activation email to customer."""
    if not SMTP_USER or not SMTP_PASS:
        print(f"⚠️  SMTP credentials not set. License key generated for {to_email}: {license_key}")
        return False

    display_name = name if name else "DropDial Customer"

    subject = f"Your DropDial Pro License Key 🚀"

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f1115; color: #e6e8eb; margin: 0; padding: 24px; }}
            .container {{ max-width: 560px; margin: 0 auto; background: #1a1d24; border-radius: 12px; border: 1px solid #2b303a; padding: 32px; }}
            .header {{ text-align: center; margin-bottom: 24px; }}
            .title {{ font-size: 24px; font-weight: 700; color: #ffffff; margin-top: 10px; }}
            .tagline {{ font-size: 14px; color: #9ea4ac; }}
            .box {{ background: #12141a; border: 1px solid #333a46; border-radius: 8px; padding: 18px; margin: 24px 0; text-align: center; }}
            .key-label {{ font-size: 12px; text-transform: uppercase; letter-spacing: 1px; color: #ff6b35; font-weight: 700; margin-bottom: 8px; }}
            .license-key {{ font-family: 'SF Mono', Consolas, Monaco, monospace; font-size: 13px; color: #ffffff; word-break: break-all; background: #090a0d; padding: 12px; border-radius: 6px; border: 1px solid #262a33; display: block; }}
            .steps {{ margin: 20px 0; padding-left: 20px; line-height: 1.6; font-size: 14px; color: #c4c9d4; }}
            .steps li {{ margin-bottom: 8px; }}
            .footer {{ text-align: center; font-size: 12px; color: #6e737b; margin-top: 32px; border-top: 1px solid #262a33; padding-top: 16px; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <div class="title">Welcome to DropDial Pro!</div>
                <div class="tagline">Thank you for your purchase, {display_name}.</div>
            </div>

            <p style="font-size: 14px; line-height: 1.6; color: #c4c9d4;">
                Your lifetime license key has been generated and is ready to activate on both macOS and Windows.
            </p>

            <div class="box">
                <div class="key-label">Your License Key</div>
                <div class="license-key">{license_key}</div>
            </div>

            <h3 style="font-size: 16px; color: #ffffff; margin-bottom: 8px;">How to Activate:</h3>
            <ol class="steps">
                <li>Open <strong>DropDial</strong> on your Mac or Windows PC.</li>
                <li>Click the DropDial icon in your menu bar (Mac) or system tray (Windows).</li>
                <li>Select <strong>Activate DropDial Pro...</strong>.</li>
                <li>Paste your license key and click <strong>Activate DropDial Pro</strong>.</li>
            </ol>

            <p style="font-size: 13px; color: #9ea4ac; line-height: 1.5;">
                DropDial works 100% offline — your key is verified cryptographically right on your machine with no internet connection required.
            </p>

            <div class="footer">
                DropDial • Fast, Private Desktop File Tools<br>
                Need assistance? Reply directly to this email or reach us at {FROM_EMAIL}.
            </div>
        </div>
    </body>
    </html>
    """

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{FROM_NAME} <{FROM_EMAIL}>"
    msg["To"] = to_email

    text_content = f"DropDial Pro License Key\n\nCustomer: {display_name}\nLicense Key: {license_key}\n\nActivate inside DropDial menu > Activate DropDial Pro."
    msg.attach(MIMEText(text_content, "plain"))
    msg.attach(MIMEText(html_content, "html"))

    try:
        server = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15)
        server.starttls()
        server.login(SMTP_USER, SMTP_PASS)
        server.sendmail(FROM_EMAIL, [to_email], msg.as_string())
        server.quit()
        print(f"📧 License email successfully sent to: {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send email to {to_email}: {e}")
        return False


class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/" or parsed.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status":"ok","service":"dropdial-licensing"}')
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        parsed = urlparse(self.path)
        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length)

        # 1. Razorpay Webhook Endpoint
        if parsed.path == "/webhook/razorpay":
            self.handle_razorpay_webhook(raw_body)
        # 2. Manual Issue Endpoint (Admin only)
        elif parsed.path == "/admin/issue":
            self.handle_admin_issue(raw_body)
        else:
            self.send_response(404)
            self.end_headers()

    def handle_razorpay_webhook(self, raw_body: bytes):
        received_sig = self.headers.get("X-Razorpay-Signature", "")

        # Verify HMAC-SHA256 signature if secret is configured
        if WEBHOOK_SECRET and WEBHOOK_SECRET != "change_me_to_your_webhook_secret":
            expected_sig = hmac.new(
                WEBHOOK_SECRET.encode("utf-8"),
                raw_body,
                hashlib.sha256
            ).hexdigest()

            if not hmac.compare_digest(received_sig, expected_sig):
                print("❌ Invalid Razorpay webhook signature!")
                self.send_response(400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"error":"invalid_signature"}')
                return

        try:
            data = json.loads(raw_body.decode("utf-8"))
        except Exception as e:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error":"invalid_json"}')
            return

        event = data.get("event")
        print(f"🔔 Received Razorpay event: {event}")

        # Razorpay events: payment.captured or order.paid
        if event in ("payment.captured", "order.paid"):
            payload = data.get("payload", {})
            payment = payload.get("payment", {}).get("entity", {})

            email = payment.get("email") or ""
            notes = payment.get("notes") or {}
            name = notes.get("name") or notes.get("customer_name") or email.split("@")[0]
            payment_id = payment.get("id") or ""
            amount = str(payment.get("amount", 0) / 100.0)

            if email:
                key = keygen.generate_license(email=email, name=name, tier="pro")
                record_license(email=email, name=name, key=key, payment_id=payment_id, amount=amount)
                send_license_email(to_email=email, name=name, license_key=key)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok"}')

    def handle_admin_issue(self, raw_body: bytes):
        auth_header = self.headers.get("Authorization", "")
        if auth_header != f"Bearer {ADMIN_KEY}":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        try:
            data = json.loads(raw_body.decode("utf-8"))
            email = data["email"]
            name = data.get("name", "")
            tier = data.get("tier", "pro")
        except Exception:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error":"email is required in json"}')
            return

        key = keygen.generate_license(email=email, name=name, tier=tier)
        record_license(email=email, name=name, key=key, payment_id="manual", amount="0")
        if data.get("send_email", False):
            send_license_email(to_email=email, name=name, license_key=key)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        resp = json.dumps({"status": "ok", "email": email, "license_key": key})
        self.wfile.write(resp.encode("utf-8"))


def run():
    server = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), WebhookHandler)
    print(f"🚀 DropDial License Webhook Server running on http://0.0.0.0:{PORT}")
    print(f"   Razorpay Webhook URL: http://your-domain.com/webhook/razorpay")
    print(f"   Database: {DB_FILE}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")
        server.server_close()


if __name__ == "__main__":
    run()
