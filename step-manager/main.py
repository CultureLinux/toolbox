#!/usr/bin/env python3

import argparse
from pathlib import Path
import glob

from utils import hd
from ca import create_cert, renew_cert

parser = argparse.ArgumentParser()
parser.add_argument("-m", "--mode", type=str, choices=['list', 'info', 'renew', 'create', 'server'], required=True)
parser.add_argument("-u", "--user", type=str)
parser.add_argument("-s", "--server", type=str)
parser.add_argument("-lt", "--lifetime", type=int, help="Life time in days")
args = parser.parse_args()

# Lifetime default in hours
if args.lifetime:
    lifetime = args.lifetime * 24
else:
    if args.server:
        lifetime = 2160
    elif args.user:
        lifetime = 720
    else:
        lifetime = 270

time_expired = 86400  # 1 jour en secondes

if args.mode == 'list':
    hd("List certificates")
    for file in glob.glob("*/*.crt"):
        print(file)

elif args.mode == 'info':
    hd("Certificate info")
    for file in glob.glob("*/*.crt"):
        print(f"\n>> {file}")
        from subprocess import run
        run(["step", "certificate", "inspect", file, "--short"])

elif args.mode == 'renew':
    hd("Renew certificates")
    # Serveurs
    for file in glob.glob("server/*.crt"):
        if file != "server/root.crt":
            renew_cert(file, time_expired)
    # Users
    user_path = f"user/{args.user}*.crt" if args.user else "user/*.crt"
    for file in glob.glob(user_path):
        renew_cert(file, time_expired)

elif args.mode == 'create':
    if args.server:
        create_cert(args.server, cert_type='server', lifetime_hours=lifetime)
    elif args.user:
        create_cert(args.user, cert_type='user', lifetime_hours=lifetime)
    else:
        print("❌ In create mode you need to specify --user or --server")