import subprocess
from pathlib import Path
from utils import get_random_string, save_password

def run_cmd(cmd_list):
    result = subprocess.run(cmd_list, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"❌ Error: {result.stderr}")
    return result.stdout

def create_cert(name, cert_type='user', lifetime_hours=720):
    folder = 'user' if cert_type=='user' else 'server'
    crt_path = f"{folder}/{name}.crt"
    key_path = f"{folder}/{name}.key"

    print(f"Creating certificate {name} ({cert_type})...")
    run_cmd([
        "step", "ca", "certificate", name,
        crt_path, key_path,
        "--provisioner-password-file=.pawd", "-f",
        f"--not-after={lifetime_hours}h"
    ])

    if cert_type == 'user':
        pwd = get_random_string()
        save_password(f"{folder}/{name}.txt", pwd)
        run_cmd([
            "step", "certificate", "p12",
            f"{folder}/{name}.p12",
            crt_path, key_path,
            "-f", f"--password-file={folder}/{name}.txt",
            "--ca", "server/root.crt"
        ])
        # Ici tu peux appeler ta notification
        # notify_mattermost(name, pwd)
        Path(f"{folder}/{name}.txt").unlink()

def renew_cert(cert_path, time_expired_sec=86400):
    print(f"Renewing certificate {cert_path}...")
    run_cmd([
        "openssl", "x509", "-enddate", "-noout", "-in", cert_path, "-checkend", str(time_expired_sec)
    ])
    # Pour Step CA renewal
    base = Path(cert_path).stem
    run_cmd(["step", "ca", "renew", f"{base}.crt", f"{base}.key", "-f"])