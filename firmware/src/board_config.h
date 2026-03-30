#pragma once

#if defined(CONTROLLER_BOARD_WROOM) && defined(CONTROLLER_BOARD_S3)
#error "Only one controller board target may be defined"
#endif

#if !defined(CONTROLLER_BOARD_WROOM) && !defined(CONTROLLER_BOARD_S3)
#error "A controller board target must be defined by PlatformIO"
#endif

#ifndef CONTROLLER_BOARD_NAME
#error "CONTROLLER_BOARD_NAME must be defined by PlatformIO"
#endif

#if defined(CONTROLLER_BOARD_WROOM)
#define CONTROLLER_BOARD_CLASSIC_ESP32 1
#elif defined(CONTROLLER_BOARD_S3)
#define CONTROLLER_BOARD_ESP32S3 1
#endif

namespace board_config {
static constexpr const char* kBoardName = CONTROLLER_BOARD_NAME;
}
