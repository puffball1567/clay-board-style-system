#include "cbss.h"

#ifndef CBSS_DEPRECATED
#error "CBSS_DEPRECATED must be provided by the public header"
#endif

CBSS_DEPRECATED("compile-only C deprecation contract probe")
CBSS_API void deprecated_c_contract_probe(void);

int main(void) {
  return CBSS_ABI_VERSION == 0x00010015u &&
          CBSS_DRIVER_CONTRACT_VERSION == 0x00010000u &&
          CBSS_CAPABILITY_STREAM == 15u ? 0 : 1;
}
