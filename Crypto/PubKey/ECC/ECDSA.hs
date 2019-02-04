-- | /WARNING:/ Signature operations may leak the private key. Signature verification
-- should be safe.
{-# LANGUAGE DeriveDataTypeable #-}
module Crypto.PubKey.ECC.ECDSA
    ( Signature(..)
    , PublicPoint
    , PublicKey(..)
    , PrivateNumber
    , PrivateKey(..)
    , KeyPair(..)
    , toPublicKey
    , toPrivateKey
    , signWith
    , sign
    , verify
    ) where

import Control.Monad
import Data.Data

import Crypto.Hash
import Crypto.Internal.ByteArray (ByteArrayAccess)
import Crypto.Number.ModArithmetic (inverse)
import Crypto.Number.Generate
import Crypto.PubKey.ECC.Types
import Crypto.PubKey.ECC.Prim
import Crypto.PubKey.Internal (dsaTruncHash)
import Crypto.Random.Types

-- | Represent a ECDSA signature namely R and S.
data Signature = Signature
    { sign_r :: Integer -- ^ ECDSA r
    , sign_s :: Integer -- ^ ECDSA s
    } deriving (Show,Read,Eq,Data,Typeable)

-- | ECDSA Private Key.
data PrivateKey = PrivateKey
    { private_curve :: Curve
    , private_d     :: PrivateNumber
    } deriving (Show,Read,Eq,Data,Typeable)

-- | ECDSA Public Key.
data PublicKey = PublicKey
    { public_curve :: Curve
    , public_q     :: PublicPoint
    } deriving (Show,Read,Eq,Data,Typeable)

-- | ECDSA Key Pair.
data KeyPair = KeyPair Curve PublicPoint PrivateNumber
    deriving (Show,Read,Eq,Data,Typeable)

-- | Public key of a ECDSA Key pair.
toPublicKey :: KeyPair -> PublicKey
toPublicKey (KeyPair curve pub _) = PublicKey curve pub

-- | Private key of a ECDSA Key pair.
toPrivateKey :: KeyPair -> PrivateKey
toPrivateKey (KeyPair curve _ priv) = PrivateKey curve priv

-- | Sign message using the private key and an explicit k number.
--
-- /WARNING:/ Vulnerable to timing attacks.
signWith :: (ByteArrayAccess msg, HashAlgorithm hash)
         => Integer    -- ^ k random number
         -> PrivateKey -- ^ private key
         -> hash       -- ^ hash function
         -> msg        -- ^ message to sign
         -> Maybe Signature
signWith k (PrivateKey curve d) hashAlg msg = do
    let z = dsaTruncHash hashAlg msg n
        CurveCommon _ _ g n _ = common_curve curve
    let point = pointMul curve k g
    r <- case point of
              PointO    -> Nothing
              Point x _ -> return $ x `mod` n
    kInv <- inverse k n
    let s = kInv * (z + r * d) `mod` n
    when (r == 0 || s == 0) Nothing
    return $ Signature r s

-- | Sign message using the private key.
--
-- /WARNING:/ Vulnerable to timing attacks.
sign :: (ByteArrayAccess msg, HashAlgorithm hash, MonadRandom m)
     => PrivateKey -> hash -> msg -> m Signature
sign pk hashAlg msg = do
    k <- generateBetween 1 (n - 1)
    case signWith k pk hashAlg msg of
         Nothing  -> sign pk hashAlg msg
         Just sig -> return sig
  where n = ecc_n . common_curve $ private_curve pk

-- | Verify a bytestring using the public key.
verify :: (ByteArrayAccess msg, HashAlgorithm hash) => hash -> PublicKey -> Signature -> msg -> Bool
verify _       (PublicKey _ PointO) _ _ = False
verify hashAlg pk@(PublicKey curve q) (Signature r s) msg
    | r < 1 || r >= n || s < 1 || s >= n = False
    | otherwise = maybe False (r ==) $ do
        w <- inverse s n
        let z  = dsaTruncHash hashAlg msg n
            u1 = z * w `mod` n
            u2 = r * w `mod` n
            x  = pointAddTwoMuls curve u1 g u2 q
        case x of
             PointO     -> Nothing
             Point x1 _ -> return $ x1 `mod` n
  where n = ecc_n cc
        g = ecc_g cc
        cc = common_curve $ public_curve pk
