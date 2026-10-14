# ⛏ MineOS — Linux-based OS ISO

> OS basé sur **Debian Live** avec Chrome, Wine (.exe), bureau personnalisé Minecraft-themed.

## 🔧 Ce que contient cet ISO

| Composant | Détail |
|-----------|--------|
| Base | Debian 12 (Bookworm) Live |
| Bureau | Openbox + LightDM |
| Navigateur | Google Chrome (stable) |
| Compatibilité .exe | Wine 8.x + Winetricks |
| Terminal | Tilix |
| Gestionnaire de fichiers | Thunar |
| Thème | MineOS Green Dark (GTK) |
| Bootloader | ISOLINUX + GRUB EFI |
| Architecture | x86_64 |

## 🚀 Compiler l'ISO via GitHub Actions

1. **Fork ce repo** sur ton compte GitHub
2. Va dans **Actions** → active les workflows
3. Clique sur **Build MineOS ISO** → **Run workflow**
4. Attend ~20-30 min
5. Télécharge l'ISO dans les **Artifacts** de la run

## 💿 Flasher l'ISO

```bash
# Linux / macOS
sudo dd if=mineos.iso of=/dev/sdX bs=4M status=progress && sync

# Windows : utiliser Rufus ou balenaEtcher
```

## 📁 Structure du projet

```
mineos-iso/
├── .github/workflows/build.yml   # CI/CD GitHub Actions
├── scripts/
│   ├── build.sh                  # Script de build principal
│   ├── customize.sh              # Customisation du rootfs
│   └── install-packages.sh       # Installation des paquets
├── configs/
│   ├── lb-config                 # Config live-build
│   ├── openbox/                  # Config bureau Openbox
│   ├── lightdm/                  # Config écran de connexion
│   └── gtk-theme/                # Thème visuel MineOS
├── rootfs/
│   ├── etc/                      # Config système
│   ├── usr/local/bin/            # Scripts système MineOS
│   └── home/user/                # Home par défaut
└── README.md
```

## 🖥 Applications incluses

- **Google Chrome** — Navigateur web complet
- **Wine** — Lancer des `.exe` Windows
- **Winetricks** — Helper Wine (DirectX, .NET, VCRedist...)
- **Thunar** — Explorateur de fichiers
- **Tilix** — Terminal
- **Mousepad** — Éditeur de texte (Bloc-notes)
- **Geany** — IDE léger
- **VLC** — Lecteur multimédia
- **GIMP** — Édition d'images
- **MineOS Panel** — Barre des tâches custom

## ⚙️ Pré-requis pour build local

```bash
sudo apt install live-build debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin
```
