<?php

namespace App;

use PHPMailer\PHPMailer\Exception;
use PHPMailer\PHPMailer\PHPMailer;

class Mailer
{
    public static function envoyer(string $destinataire, string $sujet, string $texte): bool
    {
        $mail = new PHPMailer(true);
        try {
            $mail->isSMTP();
            $mail->Host = Config::get('SMTP_HOST');
            $mail->Port = (int) Config::get('SMTP_PORT', '587');
            $mail->SMTPAuth = Config::get('SMTP_USER') !== '';
            $mail->Username = Config::get('SMTP_USER');
            $mail->Password = Config::get('SMTP_PASS');
            $mail->Timeout = 10;

            $chiffrement = Config::get('SMTP_SECURE', 'tls');
            if ($chiffrement === 'ssl') {
                $mail->SMTPSecure = PHPMailer::ENCRYPTION_SMTPS;
            } elseif ($chiffrement === 'tls') {
                $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
            } else {
                $mail->SMTPAutoTLS = false;
            }

            $mail->CharSet = PHPMailer::CHARSET_UTF8;
            $mail->setFrom(Config::get('MAIL_FROM'), 'Boggle');
            $mail->addAddress($destinataire);
            $mail->Subject = $sujet;
            $mail->Body = $texte;
            $mail->send();
            return true;
        } catch (Exception $e) {
            error_log('Email non envoye : ' . $mail->ErrorInfo);
            return false;
        }
    }
}
