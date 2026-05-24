"use client";

import { ConnectButton as RainbowConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useBalance } from "wagmi";
import { ADDRESSES } from "../../lib/contracts/addresses";

export function ConnectButton() {
  return (
    <RainbowConnectButton.Custom>
      {({ account, chain, openAccountModal, openChainModal, openConnectModal, mounted }) => {
        const ready = mounted;
        const connected = ready && account && chain;

        return (
          <div
            {...(!ready && {
              "aria-hidden": true,
              style: { opacity: 0, pointerEvents: "none", userSelect: "none" },
            })}
          >
            {!connected ? (
              <button onClick={openConnectModal}
                className="px-4 py-2 rounded-lg bg-accent-blue text-bg-primary font-mono font-semibold text-sm hover:bg-accent-blue/80 transition-all">
                Connect Wallet
              </button>
            ) : chain.unsupported ? (
              <button onClick={openChainModal}
                className="px-4 py-2 rounded-lg bg-red-500/20 border border-red-500/40 text-red-400 font-mono text-sm hover:bg-red-500/30 transition-all">
                Wrong Network
              </button>
            ) : (
              <div className="flex items-center gap-2">
                {/* Chain badge */}
                <button onClick={openChainModal}
                  className="px-2 py-1.5 rounded-lg bg-bg-tertiary border border-border-subtle hover:border-border-default font-mono text-xs text-text-secondary flex items-center gap-1.5 transition-all">
                  {chain.hasIcon && (
                    <div className="w-3.5 h-3.5 rounded-full overflow-hidden">
                      {chain.iconUrl && <img alt={chain.name ?? "chain icon"} src={chain.iconUrl} className="w-full h-full" />}
                    </div>
                  )}
                  {chain.name}
                </button>
                {/* Account */}
                <button onClick={openAccountModal}
                  className="px-3 py-1.5 rounded-lg bg-bg-tertiary border border-border-subtle hover:border-accent-blue font-mono text-xs text-text-primary flex items-center gap-2 transition-all">
                  {account.ensAvatar ? (
                    <img src={account.ensAvatar} alt={account.displayName} className="w-4 h-4 rounded-full" />
                  ) : (
                    <div className="w-4 h-4 rounded-full bg-accent-blue/40 flex items-center justify-center text-[8px] text-accent-blue font-bold">
                      {account.address.slice(2, 4).toUpperCase()}
                    </div>
                  )}
                  {account.displayName}
                </button>
              </div>
            )}
          </div>
        );
      }}
    </RainbowConnectButton.Custom>
  );
}
