{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE Trustworthy #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Control.Monad.Except.Union ( MonadErrorMap (emap), (:∈), (:⊆), Raises
                                  , (@:), raise, raify, reraise, typesExhausted
                                  , singleError, raiseFrom
                                  , E.Except, ExceptT
                                  , E.runExceptT, E.runExcept ) where

import safe Control.Arrow (left)
import safe Control.Monad.Except (MonadError, ExceptT, withExceptT, throwError)
import safe qualified Control.Monad.Except as E
import Data.OpenUnion.Internal ( (:<), (:\), Union (Union), (@>)
                               , liftUnion, restrict, typesExhausted )
import safe Data.Typeable (Typeable)
import GHC.Exts (Constraint)

class (MonadError e m, MonadError e' m') => MonadErrorMap e m e' m' | e m' -> m where
    emap :: (e -> e') -> m a -> m' a

instance (Monad m) => MonadErrorMap e (ExceptT e m) e' (ExceptT e' m) where
    emap = withExceptT

-- instance (Monad m, MonadError e' (t m), MonadTrans t) => MonadErrorMap e (ExceptT e m) e' (t m) where
--     emap f = go <=< lift . runExceptT where
--         go :: forall m' a. (MonadError e' m') => (Either e a) -> m' a
--         go = either (throwError . f) pure

instance MonadErrorMap e (Either e) e' (Either e') where
    emap = left

-- instance (MonadErrorMap e m e' m', MFunctor t, MonadError e (t m), MonadError e' (t m')) => MonadErrorMap e (t m) e' (t m') where
--     emap f = hoist $ emap f

type family (:∈) (x :: *) (ys :: [*]) :: Constraint where
    x :∈ '[y]      = (x ~ y)
    x :∈ (x ': ys) = ()
    x :∈ (y ': ys) = x :∈ ys

type family (:⊆) (s :: [*]) (s' :: [*]) :: Constraint where
    '[]      :⊆ s' = ()
    (a ': s) :⊆ s' = (s :⊆ s', a :∈ s')

instance (s :⊆ s') => s :< s'

jiggle :: Union s -> Union t
jiggle (Union s) = Union s

raise :: (Raises e s m, Typeable e) => e -> m a
raise = throwError . liftUnion

raify :: forall s m s' m' e e' a.
         ( MonadErrorMap (Union s) m (Union s') m'
         , s ~ (e ': s')
         , e' :∈ s'
         , Typeable e, Typeable e') =>
         (e -> e') -> m a -> m' a
raify f = emap f' where
    f' s = case restrict s of
        Left  u -> rejig u
        Right e -> liftUnion $ f e
    -- So there's no (s' :\ e) :⊆ s' constraint required on raify
    rejig :: Union (s' :\ e) -> Union s'
    rejig = jiggle

reraise :: forall s m s' m' e e' a.
           ( MonadErrorMap (Union s) m (Union s') m'
           , s ~ (e ': (s' :\ e'))
           , e' :∈ s'
           , Typeable e, Typeable e' ) =>
           (e -> e') -> m a -> m' a
reraise f = emap f' where
    f' s = case restrict s of
        Left  u -> rejig u
        Right e -> liftUnion $ f e
    -- Removes (s' :\ e' :\ e) :⊆ s' constaint on reraise
    rejig :: Union (s' :\ e' :\ e) -> Union s'
    rejig = jiggle

(@:) :: (s ~ (s :\ e), Typeable e) => (e -> e') -> (Union s -> e') -> Union (e ': s) -> e'
r @: l = either l r . restrict
infixr 2 @:

singleError :: (MonadErrorMap (Union '[e]) m e m', Typeable e) => m a -> m' a
singleError = emap $ id @> typesExhausted

raiseFrom :: (MonadErrorMap e m (Union s) m', e :∈ s, Typeable e) => m a -> m' a
raiseFrom = emap liftUnion

type Raises e s m = (MonadError (Union s) m, e :∈ s)
