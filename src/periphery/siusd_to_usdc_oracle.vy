# @version 0.4.3

"""
@title siUSD Price Oracle
@license GNU AGPLv3
@author Flex
@notice Provides the price of siUSD in USDC by converting siUSD to iUSD through the vault
        exchange rate and pricing iUSD off InfiniFi's accounting
@dev InfiniFi's accounting prices USDC at a fixed 1, so its iUSD price is in USDC terms
@dev InfiniFi can set the iUSD price in its accounting to any value, so we cap it at 1
"""

from ethereum.ercs import IERC4626

from ..interfaces import IInfiniFiAccounting
from ..interfaces import IPriceOracle

# ============================================================================================
# Interfaces
# ============================================================================================


implements: IPriceOracle


# ============================================================================================
# Constants
# ============================================================================================


# Contracts
ACCOUNTING: public(constant(IInfiniFiAccounting)) = IInfiniFiAccounting(0x7A5C5dbA4fbD0e1e1A2eCDBe752fAe55f6E842B3)

# Tokens
IUSD: public(constant(address)) = 0x48f9e38f3070AD8945DFEae3FA70987722E3D89c
SIUSD: public(constant(IERC4626)) = IERC4626(0xDBDC1Ef57537E34680B898E1FEBD3D68c7389bCB)

# Bound on the iUSD/USDC price
_UPPER_BOUND: constant(uint256) = 10 ** 18  # 1

# Internal constants
_WAD: constant(uint256) = 10 ** 18
_ORACLE_SCALE_FACTOR: constant(uint256) = 10 ** 24  # 10^(36 + usdc_decimals - siusd_decimals)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    # Make sure the vault unwraps to iUSD
    assert staticcall SIUSD.asset() == IUSD, "!iusd"

    # Make sure the accounting returns a sane price
    assert staticcall ACCOUNTING.price(IUSD) > 0, "!accounting"


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def get_price(scaled: bool = True) -> uint256:
    """
    @notice Get the siUSD price in terms of USDC
    @param scaled If True, returns 10^(36 + usdc_decimals - siusd_decimals) format,
                  if False, returns WAD format
    @return Price scaled to the required format
    """
    # iUSD/USDC from InfiniFi's accounting, capped at 1
    iusd_price: uint256 = min(staticcall ACCOUNTING.price(IUSD), _UPPER_BOUND)

    # siUSD --> iUSD
    iusd_per_share: uint256 = staticcall SIUSD.convertToAssets(_WAD)

    # siUSD price in USDC
    price: uint256 = iusd_per_share * iusd_price // _WAD

    # Make sure price is not zero
    assert price > 0, "wtf"

    # Scale price to the required format if needed and return
    return price * _ORACLE_SCALE_FACTOR // _WAD if scaled else price
