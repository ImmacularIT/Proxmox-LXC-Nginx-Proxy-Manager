# Branding assets

The Proxmox Summary panel deliberately references upstream-hosted artwork rather
than committing copied brand files in the initial development branch:

- Nginx Proxy Manager artwork: `https://nginxproxymanager.com/github.png`
- Approved ImmacularIT artwork, pinned to the Guacamole repository commit:
  `https://raw.githubusercontent.com/ImmacularIT/Proxmox-Itiligent-Guacamole/15c268e6fd0e6f9b441aa9f785c278c3f580171b/assets/immacularit-logo.png`

CI validates that each URL returns a PNG signature. Before a production release,
these URLs must also be verified in a real Proxmox browser session. The text and
links in the panel remain useful when remote images cannot load.
