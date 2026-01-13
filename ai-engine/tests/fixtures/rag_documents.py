from langchain_core.documents import Document


REALISTIC_DOMAINS = {
    "User Authentication": {
        "description": "Manages user accounts, authentication, authorization, and session management",
        "documents": [
            "User Authentication Domain Overview:\n\nThe User Authentication domain handles all aspects of user identity management including registration, login, password management, multi-factor authentication, and session handling. This domain ensures secure access to the system and manages user credentials.",
            "Authentication Technical Specifications:\n\n- OAuth 2.0 and OpenID Connect integration\n- JWT token generation and validation\n- Password hashing using bcrypt\n- Session management with Redis\n- Rate limiting for login attempts\n- Account lockout mechanisms\n- Password reset workflows",
            "Authentication Features and Requirements:\n\n- User registration with email verification\n- Login with username/password or social providers\n- Password strength validation\n- Two-factor authentication (2FA)\n- Password reset via email\n- Session timeout and refresh\n- Role-based access control (RBAC)\n- Account management (profile updates, deletion)",
        ],
    },
    "Payment Processing": {
        "description": "Handles payment transactions, billing, invoicing, and financial operations",
        "documents": [
            "Payment Processing Domain Overview:\n\nThe Payment Processing domain manages all financial transactions including payment collection, refunds, invoicing, and billing cycles. This domain integrates with payment gateways and ensures secure handling of sensitive financial data.",
            "Payment Technical Specifications:\n\n- Integration with Stripe and PayPal APIs\n- PCI DSS compliance requirements\n- Encrypted payment data storage\n- Transaction logging and audit trails\n- Webhook handling for payment events\n- Currency conversion support\n- Recurring billing management",
            "Payment Features and Requirements:\n\n- Credit card payment processing\n- Multiple payment method support\n- Automatic retry for failed payments\n- Refund processing\n- Invoice generation and delivery\n- Payment history and receipts\n- Subscription billing management\n- Fraud detection and prevention",
        ],
    },
    "Order Management": {
        "description": "Manages order lifecycle, inventory tracking, and fulfillment processes",
        "documents": [
            "Order Management Domain Overview:\n\nThe Order Management domain handles the complete order lifecycle from creation to fulfillment. This includes order processing, inventory management, shipping coordination, and order tracking.",
            "Order Management Technical Specifications:\n\n- Order state machine implementation\n- Inventory reservation system\n- Integration with shipping providers\n- Real-time order status updates\n- Order cancellation and modification workflows\n- Payment verification before fulfillment\n- Warehouse management integration",
            "Order Management Features and Requirements:\n\n- Order creation and validation\n- Inventory availability checking\n- Order status tracking\n- Shipping label generation\n- Order cancellation and refunds\n- Order history and search\n- Bulk order processing\n- Order notifications and updates",
        ],
    },
}


def generate_documents_for_domain(
    domain_name: str, domain_description: str
) -> list[Document]:
    domain_data = REALISTIC_DOMAINS.get(domain_name)

    if domain_data:
        documents_texts = domain_data["documents"]
    else:
        documents_texts = [
            f"Domain Overview: {domain_name}\n\n{domain_description}\n\nThis domain handles core business logic and user interactions.",
            f"Technical Specifications for {domain_name}:\n\n- Authentication and authorization mechanisms\n- Data persistence and storage patterns\n- API endpoints and service interfaces\n- Business rules and validation logic",
            f"Feature Requirements for {domain_name}:\n\nBased on the domain description: {domain_description}\n\nKey features include:\n- User management and access control\n- Data processing and transformation\n- Integration with external services\n- Reporting and analytics capabilities",
        ]

    return [
        Document(
            page_content=doc_text,
            metadata={
                "source": f"{domain_name.lower().replace(' ', '_')}_docs",
                "domain": domain_name,
            },
        )
        for doc_text in documents_texts
    ]
