#include "cbss.h"

static_assert(CBSS_ABI_VERSION == 0x00010015u,
              "unexpected CBSS ABI version");
static_assert(CBSS_DRIVER_CONTRACT_VERSION == 0x00010000u,
              "unexpected Craft Driver contract version");
static_assert(CBSS_CAPABILITY_STREAM == 15u,
              "unexpected capability id");

CBSS_DEPRECATED("compile-only C++ deprecation contract probe")
CBSS_API void deprecated_cpp_contract_probe(void);

int main() {
  return 0;
}
