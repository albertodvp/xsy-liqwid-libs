module Plutarch.Extra.FixedDecimal (
  FixedDecimal (..),
  fixedNumerator,
  fixedDenominator,
  PFixedDecimal (..),
  pfixedNumerator,
  pfixedDenominator,
  pconvertExp,
  pfromFixedDecimal,
  ptoFixedDecimal,
  ptoRational,
  punsafeMkFixedDecimal,
) where

import Data.Proxy (Proxy (Proxy))
import GHC.Real (Ratio ((:%)))
import GHC.TypeLits (KnownNat, Natural, natVal)
import Plutarch.Extra.Rational ((#%))
import Plutarch.Lift (
  PConstantDecl (PConstantRepr, PConstanted, pconstantFromRepr, pconstantToRepr),
  PUnsafeLiftDecl (PLifted),
 )
import Plutarch.Num (
  PNum,
  pabs,
  pfromInteger,
  (#*),
  (#-),
 )
import Plutarch.Rational (PFractional (pfromRational, precip, (#/)))
import Plutarch.Show (pshow')
import Plutarch.Unsafe (punsafeCoerce)
import qualified PlutusLedgerApi.V1 as PlutusTx

------ Haskell

{- | Fixed precision number. It behaves like scientific notation:
     `exp` shows to what power of base 10 an integer is multiplied.

     For example, Underlying value of 123456 with type `FixedDecimal 3` is
     `123.456 (123456 * 10 ^ -3)`. If it's coerced into `FixedDecimal 5`, it will be
     `1.23456 (123456 * 10 ^ -5)`. `FixedDecimal 0` will be identical to `Integer`.

     Note, `exp` is the negative exponent to base 10.

     Compared to 'Rational', 'Fixed' gives addition and subtraction
     as fast as regular 'PInteger', allows negative values, and does
     not require simplifications.

 @since 3.11.0
-}
newtype FixedDecimal (exp :: Natural) = FixedDecimal {numerator :: Integer}
  deriving stock (Generic, Eq, Ord, Show)

{- | Integer numerator of 'FixedDecimal'

 @since 3.11.0
-}
fixedNumerator :: forall (exp :: Natural). FixedDecimal exp -> Integer
fixedNumerator (FixedDecimal num) = num

{- | Integer denominator of 'FixedDecimal'

 @since 3.11.0
-}
fixedDenominator :: forall (exp :: Natural). (KnownNat exp) => FixedDecimal exp -> Integer
fixedDenominator _ = 10 ^ natVal (Proxy @exp)

instance (KnownNat exp) => Num (FixedDecimal exp) where
  (FixedDecimal a) + (FixedDecimal b) = FixedDecimal (a + b)
  fa@(FixedDecimal a) * (FixedDecimal b) = FixedDecimal (a * b `div` fixedDenominator fa)
  abs (FixedDecimal a) = FixedDecimal $ abs a
  signum fa@(FixedDecimal a) = FixedDecimal $ signum a * fixedDenominator fa
  negate (FixedDecimal a) = FixedDecimal (negate a)
  fromInteger i = FixedDecimal (i * 10 ^ natVal (Proxy @exp))

instance (KnownNat exp) => Fractional (FixedDecimal exp) where
  fromRational (a :% b) = FixedDecimal $ a * 10 ^ natVal (Proxy @exp) `div` b
  (FixedDecimal a) / (FixedDecimal b) = FixedDecimal $ a * 10 ^ natVal (Proxy @exp) `div` b

------ Plutarch

{- | Fixed precision number. It behaves like scientific notation:
     `exp` shows to what power of base 10 an integer is multiplied.

     For example, Underlying value of 123456 with type `PFixedDecimal 3` is
     `123.456 (123456 * 10 ^ -3)`. If it's coerced into `PFixedDecimal 5`, it will be
     `1.23456 (123456 * 10 ^ -5)`. `PFixedDecimal 0` will be identical to `PInteger`.

     Note, `exp` is the negative exponent to base 10. 'PFixed' does not support
     positive expoent.

     Compared to 'PRational', 'PFixed' gives addition and subtraction
     as fast as regular 'PInteger', allows negative values, and does
     not require simplifications.

 @since 3.11.0
-}
newtype PFixedDecimal (exp :: Natural) (s :: S)
  = PFixedDecimal (Term s PInteger)
  deriving stock
    ( -- | @since 3.11.0
      Generic
    )
  deriving anyclass
    ( -- | @since 3.11.0
      PlutusType
    , -- | @since 3.11.0
      PIsData
    , -- | @since 3.11.0
      PEq
    , -- | @since 3.11.0
      PPartialOrd
    , -- | @since 3.11.0
      POrd
    )

-- | @since 3.11.0
instance forall (exp :: Natural). DerivePlutusType (PFixedDecimal exp) where
  type DPTStrat _ = PlutusTypeNewtype

instance PUnsafeLiftDecl (PFixedDecimal unit) where
  type PLifted (PFixedDecimal unit) = FixedDecimal unit

instance PConstantDecl (FixedDecimal unit) where
  type PConstantRepr (FixedDecimal unit) = PConstantRepr Integer
  type PConstanted (FixedDecimal unit) = PFixedDecimal unit
  pconstantToRepr (FixedDecimal x) = pconstantToRepr x
  pconstantFromRepr x = FixedDecimal <$> pconstantFromRepr x

deriving newtype instance
  PlutusTx.ToData (FixedDecimal unit)

deriving newtype instance
  PlutusTx.FromData (FixedDecimal unit)

deriving newtype instance
  PlutusTx.UnsafeFromData (FixedDecimal unit)

-- | @since 3.11.0
instance forall (exp :: Natural). KnownNat exp => PShow (PFixedDecimal exp) where
  pshow' wrap z =
    wrap' $
      "PFixedDecimal "
        <> pshow (pquot # pto z # base)
        <> "."
        <> (replicateStr # pconstant baseExp #- (places # decimal) # "0")
        <> pshow decimal
    where
      baseExp = natVal (Proxy @exp)
      base = pconstant (10 ^ baseExp)
      decimal = prem # (pabs # pto z) # base
      wrap' x = if wrap then "(" <> x <> ")" else x

      places =
        pfix #$ plam $ \self x ->
          plet (pquot # x # 10) $ \q ->
            pif (q #== 0) 1 (1 + self # q)

      replicateStr :: Term s (PInteger :--> PString :--> PString)
      replicateStr =
        pfix #$ plam $ \self x str ->
          pif (0 #< x) (str <> (self # (x #- 1) # str)) ""

-- | @since 3.11.0
instance forall (exp :: Natural). KnownNat exp => PNum (PFixedDecimal exp) where
  a' #* b' =
    phoistAcyclic
      ( plam $ \a b ->
          pcon . PFixedDecimal $
            pdiv # (pfixedNumerator a * pfixedNumerator b) # pconstant (10 ^ natVal (Proxy @exp))
      )
      # a'
      # b'
  pfromInteger =
    pcon
      . PFixedDecimal
      . (* pconstant (10 ^ natVal (Proxy @exp)))
      . pconstant

-- | @since 3.11.0
instance forall (exp :: Natural). KnownNat exp => PIntegral (PFixedDecimal exp) where
  pdiv =
    phoistAcyclic $
      plam $ \x y ->
        pcon . PFixedDecimal $
          pdiv # (pto x * pconstant (10 ^ natVal (Proxy @exp))) # pto y
  pmod = phoistAcyclic $ plam $ \x y -> pcon . PFixedDecimal $ pmod # pto x # pto y
  pquot =
    phoistAcyclic $
      plam $ \x y ->
        pcon . PFixedDecimal $
          pquot # (pto x * pconstant (10 ^ natVal (Proxy @exp))) # pto y
  prem =
    phoistAcyclic $ plam $ \x y -> pcon . PFixedDecimal $ prem # pto x # pto y

instance (KnownNat exp) => PFractional (PFixedDecimal exp) where
  pfromRational ::
    forall (s :: S).
    Term s (PRational :--> PFixedDecimal exp)
  pfromRational = phoistAcyclic $
    plam $
      flip pmatch $ \(PRational num denom) ->
        pcon . PFixedDecimal $ pdiv # (num * (10 ^ natVal (Proxy @exp))) # pto denom

  a' #/ b' = go # a' # b'
    where
      go = phoistAcyclic $
        plam $ \a b ->
          pcon . PFixedDecimal $ pdiv # (pto a * pfromInteger (10 ^ natVal (Proxy @exp))) # pto b

  precip =
    phoistAcyclic $
      plam $ \x ->
        pcon . PFixedDecimal $ pdiv # pfromInteger (10 ^ (2 * natVal (Proxy @exp))) # pto x

{- | Integer numerator of 'PFixedDecimal'

 @since 3.11.0
-}
pfixedNumerator ::
  forall (s :: S) (unit :: Natural).
  Term s (PFixedDecimal unit) ->
  Term s PInteger
pfixedNumerator x = pmatch x $ \(PFixedDecimal n) -> n

{- | Integer denominator of 'PFixedDecimal'

 @since 3.11.0
-}
pfixedDenominator ::
  forall (s :: S) (unit :: Natural).
  (KnownNat unit) =>
  Term s (PFixedDecimal unit) ->
  Term s PInteger
pfixedDenominator _ = pfromInteger (10 ^ natVal (Proxy @unit))

{- | Change decimal point.

 *Caution* This function will drop precision when converting from more
 decimal points to less decimal points.

 For example, converting `1.234 :: Fixed 3` into `Fixed 1` will drop
 hundredth and thousandth place value and will give `1.2 :: Fixed 1`.

 There is not data loss going from small decimal points to big decimal points,
 but they will take up more memory.

 @since 3.11.0
-}
pconvertExp ::
  forall (exp2 :: Natural) (exp1 :: Natural) (s :: S).
  (KnownNat exp1, KnownNat exp2) =>
  Term s (PFixedDecimal exp1 :--> PFixedDecimal exp2)
pconvertExp = phoistAcyclic $
  plam $ \z ->
    let ediff = (natVal (Proxy @exp2) - natVal (Proxy @exp1))
     in pcon . PFixedDecimal $
          if ediff > 0
            then pto z * pconstant (10 ^ abs ediff)
            else pdiv # pto z #$ pconstant (10 ^ abs ediff)

{- | Convert 'PFixed' into 'PInteger'.

 *Caution* This will drop all decimal point values. For example,
 converting `12.345 :: Fixed 3` will give `12 :: Integer`. Pay close
 attention using this function.

 If one needs to retrive all decimal point values, use `pto` instead.

 @since 3.11.0
-}
pfromFixedDecimal ::
  forall (exp :: Natural) (s :: S).
  KnownNat exp =>
  Term s (PFixedDecimal exp :--> PInteger)
pfromFixedDecimal = phoistAcyclic $
  plam $ \z -> pdiv # pto z #$ pconstant (10 ^ natVal (Proxy @exp))

{- | Convert 'PInteger' into 'PFixed'.

 There is no dataloss, but takes more memory.

 @since 3.11.0
-}
ptoFixedDecimal ::
  forall (exp :: Natural) (s :: S).
  KnownNat exp =>
  Term s (PInteger :--> PFixedDecimal exp)
ptoFixedDecimal = phoistAcyclic $
  plam $ \z ->
    pcon
      . PFixedDecimal
      $ z * pconstant (10 ^ natVal (Proxy @exp))

{- | Convert 'PFixed' into 'PRational'.

 Note, it will *not* simplify. There is no data loss.

 @since 3.11.0
-}
ptoRational ::
  forall (exp :: Natural) (s :: S).
  KnownNat exp =>
  Term s (PFixedDecimal exp :--> PRational)
ptoRational = phoistAcyclic $
  plam $ \z -> pto z #% pconstant (10 ^ natVal (Proxy @exp))

{- | Make 'PFixed' from 'PInteger'.

 *Caution* 'PInteger' given will not be equal to returned 'PFixed'.
 Input ignores decimal point: `1234 :: Integer` will return `12.34 :: Fixed 2`.

 @since 3.11.0
-}
punsafeMkFixedDecimal ::
  forall (exp :: Natural) (s :: S).
  Term s (PInteger :--> PFixedDecimal exp)
punsafeMkFixedDecimal = plam punsafeCoerce
