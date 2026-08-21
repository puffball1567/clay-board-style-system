#include "cbss.h"
#include <cbss/craft.hpp>

static_assert(CBSS_ABI_VERSION == 0x00010016u,
              "unexpected CBSS ABI version");
static_assert(CBSS_DRIVER_CONTRACT_VERSION == 0x00010000u,
              "unexpected Craft Driver contract version");
static_assert(CBSS_CAPABILITY_STREAM == 15u,
              "unexpected capability id");
static_assert(CBSS_CAPABILITY_CRAFT_STYLE == 16u,
              "unexpected Craft Style capability id");
static_assert(CBSS_CAPABILITY_CRAFT_PACK == 17u,
              "unexpected Craft Pack capability id");
static_assert(CBSS_CRAFT_STYLE_PARSE_UNKNOWN_PROPERTY == 7,
              "unexpected Craft Style parse diagnostic code");
static_assert(CBSS_CRAFT_STYLE_REPLACEMENT_UNDECLARED_STYLE_SLOT == 1,
              "unexpected Craft Style replacement diagnostic code");
static_assert(CBSS_CRAFT_PACK_MISSING_CAPABILITY == 12,
              "unexpected Craft Pack diagnostic code");

CBSS_DEPRECATED("compile-only C++ deprecation contract probe")
CBSS_API void deprecated_cpp_contract_probe(void);

int main() {
  cbss::Length length = cbss::px(1.0f);
  (void)length;
  return 0;
}
