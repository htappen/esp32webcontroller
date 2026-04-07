set pagination off
set confirm off
set print thread-events off
set breakpoint pending on
target extended-remote :3333
monitor reset halt
thbreak setup
continue
