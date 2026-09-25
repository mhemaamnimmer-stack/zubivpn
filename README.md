# ZubiVPN — Chromebook

Chromebook / ChromeOS setup for ZubiVPN.

## Files

- `MAX.ovpn` — fast UDP tunnel on port 1194
- `STEALTH.ovpn` — TCP tunnel on port 443 for restrictive networks

Expected Germany exit:

```text
63.178.31.59
Frankfurt, Germany
```

## Chromebook setup

### 1. Enable Linux

On the Chromebook:

```text
Settings → About ChromeOS → Developers → Linux development environment → Turn on
```

### 2. Install Git

Open the Linux Terminal and run:

```bash
sudo apt update
sudo apt install -y git
```

### 3. Download ZubiVPN

```bash
cd ~
git clone https://github.com/mhemaamnimmer-stack/zubivpn.git
cd zubivpn
ls
```

You should see:

```text
MAX.ovpn
STEALTH.ovpn
README.md
```

## Connect

Install an OpenVPN-compatible app on the Chromebook, then import `MAX.ovpn`.

Use your own ZubiVPN username and password when prompted.

Try `MAX.ovpn` first. If UDP is blocked on the network, import `STEALTH.ovpn` instead.

## Verify

After connecting, open:

```text
https://checkip.amazonaws.com
```

The public IPv4 should be:

```text
63.178.31.59
```

If it is not `63.178.31.59`, disconnect and treat the VPN as not verified.

## Update later

To pull new profiles or fixes:

```bash
cd ~/zubivpn
git pull
```

## Notes

- Do not put account passwords, tokens, private keys, or Discord/bot secrets in this public repository.
- Each friend should use their own ZubiVPN account.
- `MAX` uses UDP/1194.
- `STEALTH` uses TCP/443.
