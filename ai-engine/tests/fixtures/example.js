/**
 * React component for managing shopping cart functionality in an e-commerce application.
 * Handles item management, quantity updates, price calculations, and checkout initiation.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useDispatch, useSelector } from 'react-redux';
import { toast } from 'react-toastify';

import {
  addItemToCart,
  removeItemFromCart,
  updateItemQuantity,
  clearCart,
  fetchCartItems
} from '../store/slices/cartSlice';
import { initiateCheckout } from '../store/slices/checkoutSlice';
import { formatCurrency } from '../utils/currency';
import { trackEvent } from '../analytics/tracking';

import CartItem from './CartItem';
import PriceBreakdown from './PriceBreakdown';
import CheckoutButton from './CheckoutButton';
import EmptyCart from './EmptyCart';

const ShoppingCart = ({ isOpen, onClose, className = '' }) => {
  const dispatch = useDispatch();
  const { items, totalItems, subtotal, shipping, tax, total, loading, error } = useSelector(state => state.cart);
  const { user } = useSelector(state => state.auth);

  const [localLoading, setLocalLoading] = useState(false);
  const [validationErrors, setValidationErrors] = useState({});

  useEffect(() => {
    if (isOpen && user) {
      dispatch(fetchCartItems(user.id));
    }
  }, [isOpen, user, dispatch]);

  const handleQuantityChange = useCallback(async (itemId, newQuantity) => {
    if (newQuantity < 1) {
      handleRemoveItem(itemId);
      return;
    }

    if (newQuantity > 99) {
      toast.error('Maximum quantity is 99');
      return;
    }

    setLocalLoading(true);
    try {
      await dispatch(updateItemQuantity({ itemId, quantity: newQuantity })).unwrap();
      trackEvent('cart_item_quantity_updated', { itemId, newQuantity });
    } catch (error) {
      toast.error('Failed to update quantity');
      console.error('Quantity update error:', error);
    } finally {
      setLocalLoading(false);
    }
  }, [dispatch]);

  const handleRemoveItem = useCallback(async (itemId) => {
    setLocalLoading(true);
    try {
      await dispatch(removeItemFromCart(itemId)).unwrap();
      toast.success('Item removed from cart');
      trackEvent('cart_item_removed', { itemId });
    } catch (error) {
      toast.error('Failed to remove item');
      console.error('Remove item error:', error);
    } finally {
      setLocalLoading(false);
    }
  }, [dispatch]);

  const handleClearCart = useCallback(async () => {
    if (!window.confirm('Are you sure you want to clear your cart?')) {
      return;
    }

    setLocalLoading(true);
    try {
      await dispatch(clearCart()).unwrap();
      toast.success('Cart cleared');
      trackEvent('cart_cleared');
    } catch (error) {
      toast.error('Failed to clear cart');
      console.error('Clear cart error:', error);
    } finally {
      setLocalLoading(false);
    }
  }, [dispatch]);

  const handleCheckout = useCallback(async () => {
    const errors = validateCartItems(items);
    setValidationErrors(errors);

    if (Object.keys(errors).length > 0) {
      toast.error('Please resolve cart issues before checkout');
      return;
    }

    if (!user) {
      toast.error('Please sign in to proceed with checkout');
      return;
    }

    setLocalLoading(true);
    try {
      const checkoutData = {
        items: items.map(item => ({
          productId: item.productId,
          quantity: item.quantity,
          price: item.price
        })),
        userId: user.id,
        subtotal,
        shipping,
        tax,
        total
      };

      const result = await dispatch(initiateCheckout(checkoutData)).unwrap();

      trackEvent('checkout_initiated', {
        totalItems,
        totalAmount: total,
        userId: user.id
      });

      // Redirect to checkout page
      window.location.href = `/checkout/${result.checkoutId}`;
    } catch (error) {
      toast.error('Failed to initiate checkout');
      console.error('Checkout error:', error);
    } finally {
      setLocalLoading(false);
    }
  }, [items, user, subtotal, shipping, tax, total, totalItems, dispatch]);

  const validateCartItems = (cartItems) => {
    const errors = {};

    cartItems.forEach(item => {
      if (!item.inStock) {
        errors[item.id] = 'Item is out of stock';
      } else if (item.quantity > item.maxQuantity) {
        errors[item.id] = `Maximum available quantity is ${item.maxQuantity}`;
      } else if (item.price !== item.currentPrice) {
        errors[item.id] = 'Price has changed since item was added';
      }
    });

    return errors;
  };

  const isCartValid = Object.keys(validationErrors).length === 0;
  const isCheckoutDisabled = loading || localLoading || !isCartValid || totalItems === 0;

  if (!isOpen) return null;

  return (
    <div className={`shopping-cart ${className}`}>
      <div className="cart-header">
        <h2>Shopping Cart ({totalItems} items)</h2>
        <button
          className="close-button"
          onClick={onClose}
          aria-label="Close cart"
        >
          ×
        </button>
      </div>

      <div className="cart-content">
        {error && (
          <div className="error-message">
            {error}
          </div>
        )}

        {loading ? (
          <div className="loading-state">
            Loading cart items...
          </div>
        ) : items.length === 0 ? (
          <EmptyCart onContinueShopping={onClose} />
        ) : (
          <>
            <div className="cart-items">
              {items.map(item => (
                <CartItem
                  key={item.id}
                  item={item}
                  onQuantityChange={handleQuantityChange}
                  onRemove={handleRemoveItem}
                  error={validationErrors[item.id]}
                  disabled={localLoading}
                />
              ))}
            </div>

            <PriceBreakdown
              subtotal={subtotal}
              shipping={shipping}
              tax={tax}
              total={total}
            />

            <div className="cart-actions">
              <button
                className="clear-cart-button"
                onClick={handleClearCart}
                disabled={localLoading}
              >
                Clear Cart
              </button>

              <CheckoutButton
                onClick={handleCheckout}
                disabled={isCheckoutDisabled}
                loading={localLoading}
                total={total}
              />
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default ShoppingCart;
