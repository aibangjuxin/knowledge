Upgrading Oh My Zsh is a straightforward process. Here are the steps you can follow to ensure your Oh My Zsh installation is up-to-date:

### 1. Manual Update

You can manually update Oh My Zsh using its built-in command-line utility. Follow these steps:

1. Open your terminal.
2. Run the following command:
   ```sh
   omz update
   ```
   This command will start the Oh My Zsh update process and check for any updates since the last time you updated[4](4)[5](5).

### 2. Automatic Update

Oh My Zsh can also be configured to check for updates automatically. You can set this up by modifying your `~/.zshrc` file:

1. Open your `~/.zshrc` file in a text editor.
2. Add one of the following lines before Oh My Zsh is loaded, depending on your preference:

   - **Automatic update without confirmation prompt:**
     ```sh
     zstyle ':omz:update' mode auto
     ```

   - **Offer a reminder every few days if updates are available:**
     ```sh
     zstyle ':omz:update' mode reminder
     ```

   - **Disable automatic updates entirely:**
     ```sh
     zstyle ':omz:update' mode disabled
     ```

### 3. Updating Custom Plugins

If you have custom plugins installed, you can ensure they are updated along with Oh My Zsh by modifying the `upgrade.sh` script:

1. Open the `upgrade.sh` script located at `$ZSH/tools/upgrade.sh`.
2. Add the following lines before the `exit` command:
   ```sh
   printf "\n${BLUE}%s${RESET}\n" "Updating custom plugins"
   cd custom/plugins
   for plugin in */; do
     if [ -d "$plugin/.git" ]; then
       printf "${YELLOW}%s${RESET}\n" "${plugin%/}"
       git -C "$plugin" pull
     fi
   done
   ```
   This will ensure that your custom plugins are updated whenever you update Oh My Zsh[2](2).

### Deprecated Methods

Previously, the command `upgrade_oh_my_zsh` was used to update Oh My Zsh, but it is now deprecated. You should use `omz update` instead[3](3).

By following these steps, you can keep your Oh My Zsh installation and any custom plugins up-to-date, ensuring you have the latest features and improvements.
[1] https://github.com/ohmyzsh/ohmyzsh/issues/2929
[2] https://unix.stackexchange.com/questions/477258/how-to-auto-update-custom-plugins-in-oh-my-zsh
[3] https://stackoverflow.com/questions/17648621/how-do-i-update-zsh-to-the-latest-version
[4] https://toniflorithomar.medium.com/how-to-update-oh-my-zsh-4b71aa6c59d6
[5] https://futurestud.io/tutorials/how-to-manually-update-oh-my-zsh
[6] https://unix.stackexchange.com/questions/339980/fail-to-update-upgrade-oh-my-zsh-package-with-sudo-pacman-s-oh-my-zsh-command
[7] https://medium.com/@kjdeluna/upgrade-your-terminal-experience-with-zsh-oh-my-zsh-and-powerlevel10k-d2aabf145112
[8] https://ohmyz.sh/
[9] https://arcolinuxforum.com/viewtopic.php?t=2553
[10] https://github.com/ohmyzsh/ohmyzsh
[11] https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH
[12] https://www.reddit.com/r/zsh/comments/13ekut5/ohmyzsh_without_ohmyzsh/
[13] https://www.youtube.com/watch?v=yqKimk-AFY8
[14] https://www.youtube.com/watch?v=3Q_g_PB-j2A
