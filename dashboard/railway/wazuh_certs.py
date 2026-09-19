#!/usr/bin/env python3
"""Deterministic deploy-time TLS certificate generation for Wazuh on Railway.

Railway private DNS (<service>.railway.internal) differs from Wazuh's compose
hostnames, and Railway has no shared volumes, so no init container can hand out
certificates. Instead every service derives the SAME root CA deterministically
from the shared WAZUH_CA_SEED secret and issues its own leaf for its actual
RAILWAY_PRIVATE_DOMAIN. Keys are a pure function of (seed, salt), so all three
services independently produce mutually-trusting, byte-identical material that
survives restarts and redeploys.

Usage: wazuh_certs.py <manager|indexer|dashboard> <output_dir>
"""
import hashlib
import os
import sys
from datetime import datetime, timezone

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

# Order of the P-256 group (public constant, needed to keep the scalar valid).
P256_ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
NOT_BEFORE = datetime(2026, 1, 1, tzinfo=timezone.utc)
NOT_AFTER = datetime(2049, 1, 1, tzinfo=timezone.utc)

SEED = os.environ["WAZUH_CA_SEED"]
DOMAIN = os.environ["RAILWAY_PRIVATE_DOMAIN"]

LEAF_CN = {
    "manager": "wazuh-manager",
    "indexer": "wazuh-indexer",
    "dashboard": "wazuh-dashboard",
}


def derive_key(salt: str) -> ec.EllipticCurvePrivateKey:
    scalar = int.from_bytes(hashlib.sha512(f"{SEED}|{salt}".encode()).digest(), "big")
    return ec.derive_private_key(scalar % P256_ORDER, ec.SECP256R1())


def serial_for(salt: str) -> int:
    return int.from_bytes(hashlib.sha256(f"serial|{salt}".encode()).digest()[:16], "big")


def name_for(cn: str) -> x509.Name:
    return x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, cn),
            x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Wazuh"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Wazuh"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "California"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        ]
    )


def build_cert(subject, issuer_name, public_key, signing_key, is_ca, sans, salt):
    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer_name)
        .public_key(public_key)
        .serial_number(serial_for(salt))
        .not_valid_before(NOT_BEFORE)
        .not_valid_after(NOT_AFTER)
        .add_extension(x509.BasicConstraints(ca=is_ca, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=is_ca,
                crl_sign=is_ca,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(x509.SubjectKeyIdentifier.from_public_key(public_key), critical=False)
    )
    if sans:
        builder = builder.add_extension(
            x509.SubjectAlternativeName([x509.DNSName(d) for d in sans]), critical=False
        )
    return builder.sign(signing_key, hashes.SHA256())


def write(path: str, data: bytes, private: bool) -> None:
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, 0o600 if private else 0o644)


def main() -> None:
    role, out_dir = sys.argv[1], sys.argv[2]
    cn = LEAF_CN[role]
    os.makedirs(out_dir, exist_ok=True)

    ca_key = derive_key("ca")
    ca_cert = build_cert(
        name_for("wazuh-railway-ca"),
        name_for("wazuh-railway-ca"),
        ca_key.public_key(),
        ca_key,
        is_ca=True,
        sans=None,
        salt="ca",
    )
    write(
        os.path.join(out_dir, "root-ca.pem"),
        ca_cert.public_bytes(serialization.Encoding.PEM),
        private=False,
    )

    leaf_salt = f"leaf|{role}|{DOMAIN}"
    leaf_key = derive_key(leaf_salt)
    leaf_cert = build_cert(
        name_for(cn),
        ca_cert.subject,
        leaf_key.public_key(),
        ca_key,
        is_ca=False,
        sans=[DOMAIN],
        salt=leaf_salt,
    )
    write(
        os.path.join(out_dir, f"{cn}.pem"),
        leaf_cert.public_bytes(serialization.Encoding.PEM),
        private=False,
    )
    write(
        os.path.join(out_dir, f"{cn}.key"),
        leaf_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ),
        private=True,
    )

    if role == "indexer":
        admin_salt = "leaf|admin"
        admin_key = derive_key(admin_salt)
        admin_cert = build_cert(
            name_for("admin"),
            ca_cert.subject,
            admin_key.public_key(),
            ca_key,
            is_ca=False,
            sans=None,
            salt=admin_salt,
        )
        write(
            os.path.join(out_dir, "admin.pem"),
            admin_cert.public_bytes(serialization.Encoding.PEM),
            private=False,
        )
        write(
            os.path.join(out_dir, "admin-key.pem"),
            admin_key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption(),
            ),
            private=True,
        )

    print(f"generated deterministic certs for role={role} cn={cn} san={DOMAIN} in {out_dir}")


if __name__ == "__main__":
    main()
