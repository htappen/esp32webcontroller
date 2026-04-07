set pagination off
set confirm off
set print thread-events off
set breakpoint pending on

target extended-remote :3333
thbreak UsbXInputGamepadBridge::begin
continue
bt
info line *$pc
next
info line *$pc
next
info line *$pc
next
info line *$pc
next
info line *$pc
bt
quit
