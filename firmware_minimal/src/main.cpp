#include <Arduino.h>
#include <driver/gpio.h>

namespace {

void print_gpio_snapshot() {
  Serial.println("gpio snapshot:");
  for (int pin = 0; pin <= GPIO_NUM_MAX; ++pin) {
    if (!GPIO_IS_VALID_GPIO(static_cast<gpio_num_t>(pin))) {
      continue;
    }

    const int level = gpio_get_level(static_cast<gpio_num_t>(pin));
    Serial.printf("  gpio%02d=%d\n", pin, level);
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("minimal esp32-s3 gpio reporter");
}

void loop() {
  print_gpio_snapshot();
  delay(1000);
}
