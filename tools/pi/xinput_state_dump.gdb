set pagination off
set confirm off
target extended-remote :3333
monitor halt

print '(anonymous namespace)::g_driver_state.interfaces_opened'
print/x '(anonymous namespace)::g_driver_state.rhport'
print/x '(anonymous namespace)::g_driver_state.control_in_ep'
print/x '(anonymous namespace)::g_driver_state.control_out_ep'
print/x '(anonymous namespace)::g_driver_state.headset_in_ep'
print/x '(anonymous namespace)::g_driver_state.headset_out_ep'
print/x '(anonymous namespace)::g_driver_state.auxiliary_in_ep'
print '(anonymous namespace)::g_driver_state.report_in_flight'
print '(anonymous namespace)::g_driver_state.report_dirty'
print '(anonymous namespace)::g_usb_xinput_transport'
bt
quit
