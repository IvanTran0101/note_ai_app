export interface RecoveryMailer {
  sendCode(mailbox: string, code: string): Promise<void>;
}
