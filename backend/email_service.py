from __future__ import annotations

import smtplib
from email.message import EmailMessage

from config import Settings


MAX_OUTBOX_MESSAGES = 50


class EmailService:
    def __init__(self, settings: Settings, outbox: list[dict]):
        self.settings = settings
        self.outbox = outbox

    @property
    def configured(self) -> bool:
        sender_is_valid = bool(
            self.settings.smtp_from
            and "example.invalid" not in self.settings.smtp_from
        )
        credentials_are_valid = bool(
            not self.settings.smtp_username or self.settings.smtp_password
        )
        return bool(
            self.settings.smtp_host
            and sender_is_valid
            and credentials_are_valid
        )

    def status(self) -> dict:
        return {
            "configured": self.configured,
            "host": self.settings.smtp_host,
            "port": self.settings.smtp_port,
            "sender": (
                self.settings.smtp_from
                if "example.invalid" not in self.settings.smtp_from
                else None
            ),
            "use_tls": self.settings.smtp_use_tls,
            "username_configured": bool(self.settings.smtp_username),
            "password_configured": bool(self.settings.smtp_password),
            "public_app_url": self.settings.public_app_url,
            "development_outbox_count": len(self.outbox),
        }

    def _deliver(self, message: EmailMessage) -> None:
        if not self.configured:
            raise RuntimeError("SMTP email delivery is not configured.")
        with smtplib.SMTP(
            self.settings.smtp_host, self.settings.smtp_port, timeout=15
        ) as smtp:
            if self.settings.smtp_use_tls:
                smtp.starttls()
            if self.settings.smtp_username:
                smtp.login(
                    self.settings.smtp_username,
                    self.settings.smtp_password or "",
                )
            smtp.send_message(message)

    def send_password_link(
        self,
        *,
        email: str,
        login_id: str,
        token: str,
        purpose: str,
    ) -> bool:
        link = f"{self.settings.public_app_url}/?password_token={token}"
        if purpose == "account_activation":
            hours = self.settings.invitation_link_hours
            subject = "Your Robotics Programming Lab account is ready"
            body = (
                "Hello,\n\n"
                "Your instructor has created a Robotics Programming Lab "
                "account for you.\n\n"
                f"Login ID: {login_id}\n\n"
                "Set your password with this one-time link:\n"
                f"{link}\n\n"
                f"The link works once and expires in {hours} hours. After "
                "setting your password, sign in with your login ID and the "
                "password you chose. If the link has expired, ask your "
                "instructor to send a new one.\n\n"
                "Your password is never sent by email.\n\n"
                "Robotics Programming Lab\n"
                "Robotics Research Lab, University of Nevada, Reno"
            )
        else:
            subject = "Reset your Robotics Programming Lab password"
            body = (
                f"Your login ID is {login_id}.\n\n"
                f"Use this one-time link to reset your password:\n{link}\n\n"
                "If you did not request this message, you can ignore it."
            )
        message_record = {
            "to": email,
            "subject": subject,
            "body": body,
            "purpose": purpose,
        }
        if not self.configured:
            self.outbox.append(message_record)
            # Development outbox only; keep the newest messages.
            del self.outbox[:-MAX_OUTBOX_MESSAGES]
            return False

        message = EmailMessage()
        message["From"] = self.settings.smtp_from
        message["To"] = email
        message["Subject"] = subject
        message.set_content(body)
        self._deliver(message)
        return True

    def send_test_message(self, recipient: str) -> None:
        message = EmailMessage()
        message["From"] = self.settings.smtp_from
        message["To"] = recipient
        message["Subject"] = "Robotics Programming Lab email test"
        message.set_content(
            "Real email delivery is configured correctly for the "
            "Robotics Programming Lab."
        )
        self._deliver(message)
