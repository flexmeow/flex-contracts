# @version 0.4.3

"""
@title siUSD Price Oracle
@license GNU AGPLv3
@author Flex
@notice Provides the price of siUSD in USDC by converting siUSD to iUSD through the vault
        exchange rate and pricing iUSD off InfiniFi's accounting
@dev InfiniFi's accounting prices USDC at a fixed 1, but can change the price to any value
@dev The accounting's iUSD price is only used if Daddy approved it, otherwise iUSD/USDC is 1
"""

from ethereum.ercs import IERC4626

from ..interfaces import IInfiniFiAccounting
from ..interfaces import IPriceOracle

# ============================================================================================
# Interfaces
# ============================================================================================


implements: IPriceOracle


# ============================================================================================
# Events
# ============================================================================================


event ApproveIusdPrice:
    iusd_price: uint256


# ============================================================================================
# Constants
# ============================================================================================


# Daddy
DADDY: public(constant(address)) = 0x4e8341C77c94cCE982AB96d92BB28D69f4638290

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
# Storage
# ============================================================================================


# iUSD/USDC price in InfiniFi's accounting approved by Daddy
approved_iusd_price: public(uint256)


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

    # Start with the peg approved
    self.approved_iusd_price = _WAD


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
    # iUSD/USDC from InfiniFi's accounting
    iusd_price: uint256 = staticcall ACCOUNTING.price(IUSD)

    # 1, unless Daddy approved it
    if iusd_price != self.approved_iusd_price:
        iusd_price = _WAD

    # siUSD --> iUSD
    iusd_per_share: uint256 = staticcall SIUSD.convertToAssets(_WAD)

    # siUSD price in USDC
    price: uint256 = iusd_per_share * iusd_price // _WAD

    # Make sure price is not zero
    assert price > 0, "wtf"

    # Scale price to the required format if needed and return
    return price * _ORACLE_SCALE_FACTOR // _WAD if scaled else price


# ============================================================================================
# Daddy functions
# ============================================================================================


@external
def approve_iusd_price(iusd_price: uint256):
    """
    @notice Approve an iUSD/USDC price set in InfiniFi's accounting
    @dev Only callable by Daddy
    @dev Any other accounting price is ignored and iUSD/USDC is 1
    @dev Cannot be above 1
    @param iusd_price The iUSD/USDC price to approve, in WAD
    """
    # Make sure caller is Daddy
    assert msg.sender == DADDY, "bad daddy"

    # Make sure the price is not above 1
    assert iusd_price <= _UPPER_BOUND, "!iusd_price"

    # Approve the price
    self.approved_iusd_price = iusd_price

    # Emit event
    log ApproveIusdPrice(iusd_price=iusd_price)
