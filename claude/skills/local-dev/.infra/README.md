
#### Traefik reverse proxy
This project uses [traefik](https://traefik.io). This proxy reserver ports http/https ports from your localhost and proxies the requests to your project containers. To expose a Docker container you need to add it to the `proxy` network and define some labels:

```yaml
version: '3.7'

services:
  app:
    image: jwilder/whoami
    networks:
      - homebot
    labels:
      - "traefik.enable=true"
      - 'traefik.http.routers.traefik.entrypoints=websecure'
      - 'traefik.http.routers.traefik.rule=Host(`whoami.homebot.test`)'
      - 'traefik.http.routers.traefik.tls=true'
      - 'traefik.http.services.traefik.loadbalancer.server.port=42069'
      - 'traefik.docker.network=homebot'

networks:
  homebot:
    external:
      name: homebot
```
