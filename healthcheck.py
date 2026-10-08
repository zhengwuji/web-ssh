"""Container health probe: talks HTTP or HTTPS depending on WEBSSH_TLS_MODE."""

import os
import ssl
import urllib.request


def main():
    port = os.getenv('PORT', '5000')
    mode = os.getenv('WEBSSH_TLS_MODE', 'off')
    scheme = 'http'
    context = None
    if mode != 'off':
        # The probe must not fail on a self-signed or not-yet-trusted cert.
        scheme = 'https'
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
    url = f'{scheme}://127.0.0.1:{port}/ready'
    with urllib.request.urlopen(url, timeout=2, context=context) as response:
        response.read(1)


if __name__ == '__main__':
    main()
