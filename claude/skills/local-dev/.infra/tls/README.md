## Generate New Certs

This should only need to be done every [398 days](https://support.apple.com/en-au/102028).

```shell
./generate-certificate.sh
```

## Cert Install

```shell
# MacOS
sudo security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" ca.pem

# Linux
sudo cp ca.pem /usr/local/share/ca-certificates/homebot.pem && sudo update-ca-certificates

# Windows (via WSL bash)
certutil.exe –addstore -enterprise –f "Root" ca.pem

# Firefox
# https://support.mozilla.org/en-US/kb/setting-certificate-authorities-firefox
# about:config > security.enterprise.roots.enabled = true
```

## Restart hbdev services to pick up new certs
```shell
hdev down
hdev up --force-recreate -d
```
