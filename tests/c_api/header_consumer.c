#include "cbss.h"

#ifndef CBSS_DEPRECATED
#error "CBSS_DEPRECATED must be provided by the public header"
#endif

CBSS_DEPRECATED("compile-only C deprecation contract probe")
CBSS_API void deprecated_c_contract_probe(void);

_Static_assert(CBSS_CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY == 7,
               "unexpected Craft Style parse diagnostic code");
_Static_assert(CBSS_CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT == 1,
               "unexpected Craft Style replacement diagnostic code");
_Static_assert(CBSS_CRAFT_PACK_MISSING_CAPABILITY == 12,
               "unexpected Craft Pack diagnostic code");

int main(void) {
  return CBSS_ABI_VERSION == 0x00010018u &&
                 CBSS_DRIVER_CONTRACT_VERSION == 0x00010000u &&
                 CBSS_CAPABILITY_CRAFT_PACK == 17u &&
                 CBSS_CAPABILITY_SUBTREE_LIFECYCLE == 18u
             ? 0
             : 1;
}
