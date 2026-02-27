import secrets, string
from pathlib import Path

def get_random_string(length=12):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))

def hd(title):
    print("\n" + "#"*24)
    print(f"######### {title}")
    print("#"*24 + "\n")

def save_password(file_path: str, password: str):
    path = Path(file_path)
    path.write_text(password)
    path.chmod(0o600)