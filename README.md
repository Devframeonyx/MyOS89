# ⛏ MineOS Gaming Edition

OS basé sur **Debian 12 Live** — optimisé gaming pour i3-7020U + 16 GB RAM.

## 🎮 Optimisations gaming incluses

| Composant | Détail |
|-----------|--------|
| **Kernel** | Liquorix (low-latency, scheduler gaming) |
| **Wine** | + DXVK (DirectX 9/10/11 → Vulkan) + WINEFSYNC |
| **GameMode** | Boost CPU governor → performance automatique en jeu |
| **MangoHud** | Overlay FPS/CPU/GPU/RAM (Shift+F12) |
| **Steam** | Proton intégré (compatibilité jeux Windows) |
| **Lutris** | GOG, Epic, Battle.net, jeux rétro |
| **Intel HD 620** | GuC/HuC activé, FBC, PSR |
| **Swappiness** | 10 (garde max en RAM) |
| **Audio** | PulseAudio low-latency (5ms fragments) |
| **GRUB** | `mitigations=off` (+10-15% CPU), `nohz_full` |

## 🚀 Compiler via GitHub Actions

1. **Fork ce repo**
2. **Actions** → **Build MineOS Gaming ISO** → **Run workflow**
3. Attendre ~30 min
4. Télécharger dans **Artifacts**

## 💿 Flasher

```bash
# Linux
sudo dd if=MineOS-Gaming-1.0.0-x86_64.iso of=/dev/sdX bs=4M status=progress && sync

# Windows : Rufus ou balenaEtcher
```

## ⌨️ Raccourcis clavier

| Touche | Action |
|--------|--------|
| `Super+Entrée` | Terminal |
| `Super+B` | Chrome |
| `Super+G` | Steam |
| `Super+L` | Lutris |
| `Super+E` | Fichiers |
| `Shift+F12` | Toggle MangoHud (overlay FPS) |
| `Shift+F1` | Toggle limite FPS |
| `Clic droit bureau` | Menu |

## 💻 Commandes terminal

```bash
exe fichier.exe          # Lance avec Wine + GameMode
exe-dxvk fichier.exe     # Wine + DXVK + MangoHud overlay
steam                    # Steam (avec GameMode)
gaming-info              # Infos GPU OpenGL
```

## 📊 RAM estimée sur i3-7020U + 16 GB

| Situation | RAM utilisée | RAM libre |
|-----------|-------------|-----------|
| Idle bureau | ~380 MB | ~15,6 GB |
| + Chrome (5 onglets) | ~900 MB | ~15,1 GB |
| + Steam ouvert | ~1,2 GB | ~14,8 GB |
| + Jeu Wine moyen | ~2,5 GB | ~13,5 GB |
