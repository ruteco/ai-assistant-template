# Alternative: yandex-disk daemon (continuous sync)

Instead of the trigger-based REST API script, you can use Yandex's official
Linux daemon for true continuous background sync of one folder. Requires one
manual, interactive step — can't be scripted.

```bash
echo "deb http://repo.yandex.ru/yandex-disk/deb/ stable main" | \
  sudo tee /etc/apt/sources.list.d/yandex-disk.list
wget -qO- http://repo.yandex.ru/yandex-disk/YANDEX-DISK-KEY.GPG | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y yandex-disk

# Interactive: prints a URL + device code, open it in any browser and confirm.
yandex-disk setup
```

`yandex-disk setup` lets you pick the local sync folder. Point it at
`workspace/` (or a subfolder) and it stays in sync continuously in the
background — no cron, no polling script needed.

Trade-off vs. the REST API script: this syncs the *whole* folder continuously
and needs that one interactive setup step; `yandex_sync.sh` is fully
scriptable up front but only syncs when you call it.
