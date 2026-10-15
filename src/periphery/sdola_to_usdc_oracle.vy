# @version 0.4.3

"""
@title sDOLA Price Oracle
@license GNU AGPLv3
@author Flex
@notice Provides the price of sDOLA in USDC by converting sDOLA to DOLA through the vault
        exchange rate and pricing DOLA/USDC off the Curve DOLA/sUSDS pool's EMA oracle
@dev The pool's EMA is in USDS terms, and USDS is atomically redeemable 1:1 for USDC through
     the PSM, so it is used as a DOLA/USDC price
@dev The DOLA/USDC price is capped at 1.01
"""

from ethereum.ercs import IERC4626

from ..interfaces import ICurveStableSwapNG
from ..interfaces import IPriceOracle

# ============================================================================================
# Interfaces
# ============================================================================================


implements: IPriceOracle


# ============================================================================================
# Constants
# ============================================================================================


# Contracts
CURVE_POOL: public(constant(ICurveStableSwapNG)) = ICurveStableSwapNG(0x8b83c4aA949254895507D09365229BC3a8c7f710)  # DOLA/sUSDS

# Tokens
DOLA: public(constant(address)) = 0x865377367054516e17014CcdED1e7d814EDC9ce4
SUSDS: public(constant(address)) = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD
SDOLA: public(constant(IERC4626)) = IERC4626(0xb45ad160634c528Cc3D2926d9807104FA3157305)

# Bound on the DOLA/USDC price
_UPPER_BOUND: constant(uint256) = 101 * 10 ** 16  # 1.01

# Internal constants
_WAD: constant(uint256) = 10 ** 18
_ORACLE_SCALE_FACTOR: constant(uint256) = 10 ** 24  # 10^(36 + usdc_decimals - sdola_decimals)


# ============================================================================================
# Constructor
# ============================================================================================


@deploy
def __init__():
    """
    @notice Initialize the contract
    """
    # Make sure the vault and the pool composition line up
    assert staticcall SDOLA.asset() == DOLA, "!dola"
    assert staticcall CURVE_POOL.coins(0) == DOLA, "!coin0"
    assert staticcall CURVE_POOL.coins(1) == SUSDS, "!coin1"

    # Make sure the pool returns a sane price
    assert staticcall CURVE_POOL.price_oracle(0) > 0, "!curve_pool"


# ============================================================================================
# View functions
# ============================================================================================


@external
@view
def get_price(scaled: bool = True) -> uint256:
    """
    @notice Get the sDOLA price in terms of USDC
    @param scaled If True, returns 10^(36 + usdc_decimals - sdola_decimals) format,
                  if False, returns WAD format
    @return Price scaled to the required format
    """
    return self._get_price(scaled)


# ============================================================================================
# Internal view functions
# ============================================================================================


@internal
@view
def _get_price(scaled: bool = True) -> uint256:
    """
    @notice Get the sDOLA price in terms of USDC
    @param scaled If True, returns 10^(36 + usdc_decimals - sdola_decimals) format,
                  if False, returns WAD format
    @return Price scaled to the required format
    """
    # DOLA/USDS from the Curve EMA, used as DOLA/USDC. `price_oracle(0)` is USDS priced in DOLA, so it is inverted
    dola_price: uint256 = min(_WAD * _WAD // staticcall CURVE_POOL.price_oracle(0), _UPPER_BOUND)

    # sDOLA --> DOLA
    dola_per_share: uint256 = staticcall SDOLA.convertToAssets(_WAD)

    # sDOLA price in USDC
    price: uint256 = dola_per_share * dola_price // _WAD

    # Make sure price is not zero
    assert price > 0, "wtf"

    # Scale price to the required format if needed and return
    return price * _ORACLE_SCALE_FACTOR // _WAD if scaled else price
