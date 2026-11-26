#include "d3d11_renderer.h"
#include <dxgi1_4.h>
#include <climits>
#include <iostream>
#include <wrl.h>

bool matches(const D3D11Renderer& renderer) {
  D3D11_TEXTURE2D_DESC desc = {};
  renderer.render_target()->GetDesc(&desc);
  return desc.Width == renderer.width() && desc.Height == renderer.height();
}

int main() {
  Microsoft::WRL::ComPtr<IDXGIFactory4> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) return 20;
  Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
  if (FAILED(factory->EnumWarpAdapter(IID_PPV_ARGS(&adapter)))) return 21;
  D3D11Renderer renderer(64, 64, adapter.Get());
  if (!matches(renderer)) return 22;
  renderer.SetSize(128, 72);
  if (renderer.width() != 128 || renderer.height() != 72 || !matches(renderer)) {
    std::cout << "reported_dimensions_do_not_match_native_texture" << std::endl;
    return 10;
  }
  renderer.SetSize(INT_MAX, INT_MAX);
  if (renderer.width() != 128 || renderer.height() != 72 || !matches(renderer)) return 11;
  renderer.SetSize(320, 180);
  if (!matches(renderer) || renderer.width() != 320 || renderer.height() != 180) return 12;
  std::cout << "native_texture_and_reported_dimensions_match_after_resize_and_failure" << std::endl;
  return 0;
}
