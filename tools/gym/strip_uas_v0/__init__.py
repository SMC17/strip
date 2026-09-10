"""Strip-UAS-v0: evidence-coupled parametric wing/UAS design-search gym.

Aerospace twin of Yard-Sea-v0. Public OSINT exploratory harness for SMC17/strip.
Not certification, not operational, not FAA AI assurance approval, not ARP6983
conformance claim — vocabulary-aligned honesty only.
"""

__version__ = "0.1.0"

from .env import DesignSearchEnv
from .wing import WingState, evaluate_l0

__all__ = [
    "DesignSearchEnv",
    "WingState",
    "evaluate_l0",
    "__version__",
]
