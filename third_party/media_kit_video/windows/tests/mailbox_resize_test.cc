#include "mailbox_swap_chain.h"
#include <climits>
#include <iostream>
#include <memory>
#include <wrl.h>
int main() {
  Microsoft::WRL::ComPtr<ID3D11Device> device;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
  const auto hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr,
      D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
      &device, nullptr, &context);
  if (FAILED(hr)) return 20;
  std::unique_ptr<MailboxSwapChain> mailbox;
  if (FAILED(MailboxSwapChain::Create(device.Get(), 64, 64, &mailbox))) return 21;
  const HANDLE original = mailbox->ReadHandleSnapshot();
  if (!original) return 22;
  const auto rejected = mailbox->Resize(INT_MAX, INT_MAX);
  if (SUCCEEDED(rejected)) return 23;
  const bool preserved = mailbox->ReadHandleSnapshot() == original;
  std::cout << "failed_resize_preserves_valid_mailbox=" << preserved << std::endl;
  if (!preserved) return 10;
  mailbox->ProducerCommit();
  if (FAILED(mailbox->Resize(128, 72)) || !mailbox->ReadHandleSnapshot()) return 24;
  mailbox->ProducerCommit();
  std::cout << "subsequent_resize_and_render=1" << std::endl;
  return 0;
}
