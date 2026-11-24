import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2';
import type { RecoveryMailer } from './recovery_mailer';
import { NoteSecurityError } from './protection_store';

/** Mailbox challenge delivery. A sender must be verified/configured in SES. */
export class SesRecoveryMailer implements RecoveryMailer {
  constructor(private readonly sender: string,
    private readonly client = new SESv2Client({ maxAttempts: 1 })) {}

  async sendCode(mailbox: string, code: string): Promise<void> {
    if (!this.sender) throw new NoteSecurityError('unavailable');
    try {
      await this.client.send(new SendEmailCommand({
        FromEmailAddress: this.sender,
        Destination: { ToAddresses: [mailbox] },
        Content: { Simple: {
          Subject: { Data: 'NoteFlow — note password recovery', Charset: 'UTF-8' },
          Body: { Text: { Charset: 'UTF-8', Data:
            `Your NoteFlow note recovery code is ${code}. It expires in 5 minutes. ` +
            'This resets one note password. It cannot recover unsynced drafts encrypted with the old password.' } },
        } },
      }), { abortSignal: AbortSignal.timeout(8000) });
    } catch { throw new NoteSecurityError('unavailable'); }
  }
}
