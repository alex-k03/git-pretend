# Run from the repository root: vhs demo/demo.tape
Output demo/demo.gif

Require git
Require starship
Require tmux
Require nvim
Require python3

Set Shell "zsh"
Set FontFamily "JetBrainsMonoNL Nerd Font"
Set FontSize 15
Set Width 1320
Set Height 620
Set Padding 16
Set WindowBar Colorful
Set BorderRadius 10
Set Theme "Catppuccin Mocha"
Set TypingSpeed 45ms

Hide
Type "sh demo/setup.sh"
Enter
Sleep 500ms
Type "export PATH=$PWD/bin:$PATH STARSHIP_CONFIG=/tmp/git-pretend-starship.toml GIT_PAGER=cat"
Enter
Type "tmux kill-session -t pretend-demo 2>/dev/null || true"
Enter
Type 'tmux new-session -d -s pretend-demo -c /tmp/api "zsh -i"'
Enter
Sleep 400ms
Type "tmux set-option -t pretend-demo status off"
Enter
Type "tmux set-option -t pretend-demo pane-border-style fg=colour238"
Enter
Type "tmux set-option -t pretend-demo pane-active-border-style fg=colour238"
Enter
Type 'tmux split-window -h -t pretend-demo -p 46 -c /tmp/api "nvim src/server.py"'
Enter
Type "tmux select-pane -t pretend-demo:0.0"
Enter
Type "tmux attach -t pretend-demo"
Enter
Sleep 1.5s
Type 'eval "$(starship init zsh)" && clear'
Enter
Sleep 1.2s
Show

Sleep 800ms
Type "git log --oneline main..HEAD"
Enter
Sleep 1.8s

Type "git pretend main..."
Enter
Sleep 2.8s

Type "git status -s"
Enter
Sleep 1.6s

Type "python3 -m unittest -v"
Enter
Sleep 2.5s

Type "git pretend done"
Enter
Sleep 2.5s

Hide
Type "tmux kill-session -t pretend-demo"
Enter
