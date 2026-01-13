package com.example.order;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.inventory.InventoryService;
import com.example.payment.PaymentService;
import com.example.shipping.ShippingService;

/**
 * Service for managing e-commerce orders including creation, validation, and fulfillment.
 */
@Service
@Transactional
public class OrderService {

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private InventoryService inventoryService;

    @Autowired
    private PaymentService paymentService;

    @Autowired
    private ShippingService shippingService;

    /**
     * Creates a new order with validation and inventory checking.
     */
    public Order createOrder(CreateOrderRequest request) throws OrderException {
        validateOrderRequest(request);

        Order order = new Order();
        order.setId(UUID.randomUUID().toString());
        order.setCustomerId(request.getCustomerId());
        order.setStatus(OrderStatus.PENDING);
        order.setCreatedAt(LocalDateTime.now());
        order.setItems(new ArrayList<>());

        BigDecimal totalAmount = BigDecimal.ZERO;

        for (OrderItemRequest itemRequest : request.getItems()) {
            if (!inventoryService.isAvailable(itemRequest.getProductId(), itemRequest.getQuantity())) {
                throw new OrderException("Insufficient inventory for product: " + itemRequest.getProductId());
            }

            OrderItem item = new OrderItem();
            item.setProductId(itemRequest.getProductId());
            item.setQuantity(itemRequest.getQuantity());
            item.setUnitPrice(itemRequest.getUnitPrice());
            item.setTotalPrice(itemRequest.getUnitPrice().multiply(BigDecimal.valueOf(itemRequest.getQuantity())));

            order.getItems().add(item);
            totalAmount = totalAmount.add(item.getTotalPrice());
        }

        order.setTotalAmount(totalAmount);

        Order savedOrder = orderRepository.save(order);

        // Reserve inventory
        for (OrderItem item : savedOrder.getItems()) {
            inventoryService.reserveInventory(item.getProductId(), item.getQuantity());
        }

        return savedOrder;
    }

    /**
     * Processes payment and updates order status.
     */
    public void processPayment(String orderId, PaymentRequest paymentRequest) throws OrderException {
        Order order = findOrderById(orderId);

        if (order.getStatus() != OrderStatus.PENDING) {
            throw new OrderException("Order is not in pending status");
        }

        try {
            PaymentResult result = paymentService.processPayment(paymentRequest, order.getTotalAmount());

            if (result.isSuccessful()) {
                order.setStatus(OrderStatus.PAID);
                order.setPaymentId(result.getPaymentId());
                orderRepository.save(order);

                initiateShipping(order);
            } else {
                order.setStatus(OrderStatus.PAYMENT_FAILED);
                orderRepository.save(order);
                releaseInventory(order);
            }
        } catch (Exception e) {
            order.setStatus(OrderStatus.PAYMENT_FAILED);
            orderRepository.save(order);
            releaseInventory(order);
            throw new OrderException("Payment processing failed", e);
        }
    }

    private void validateOrderRequest(CreateOrderRequest request) throws OrderException {
        if (request.getCustomerId() == null || request.getCustomerId().trim().isEmpty()) {
            throw new OrderException("Customer ID is required");
        }

        if (request.getItems() == null || request.getItems().isEmpty()) {
            throw new OrderException("Order must contain at least one item");
        }
    }

    private Order findOrderById(String orderId) throws OrderException {
        return orderRepository.findById(orderId)
            .orElseThrow(() -> new OrderException("Order not found: " + orderId));
    }

    private void initiateShipping(Order order) {
        shippingService.createShippingLabel(order);
        order.setStatus(OrderStatus.SHIPPED);
        orderRepository.save(order);
    }

    private void releaseInventory(Order order) {
        for (OrderItem item : order.getItems()) {
            inventoryService.releaseInventory(item.getProductId(), item.getQuantity());
        }
    }
}
