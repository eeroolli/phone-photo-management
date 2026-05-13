# Phone-side scripts

Scripts in this folder are meant to be **run on the phone** (e.g. in Termux), not on your computer.

They are kept separate from the main scripts in the project root, which run on the computer and use SSH to talk to the phone (copy, move, list, etc.).

**How to use**
- Copy or sync scripts from this folder to your device (e.g. via `scp` or `rsync` using your existing SSH config).
- Run them inside Termux (or another shell on the phone).

Example from your computer (using the project’s SSH config):
```bash
# Copy a script to the phone (path may vary)
scp -i "$SSH_KEY" -P "$DEVICE_PORT" phone_scripts/some_script.sh "$DEVICE_USER@$DEVICE_IP:~/"
# Then on the phone: ./some_script.sh
```
