const axios = require('axios');

async function testCashfree() {
    const clientId = "CF11008621D6K4KNB1QR0S73ATNTCG";
    const clientSecret = "cfsk_ma_test_885a4a8f62266759fc7fa7cce7f23c8b_fb8599bf";

    try {
        const response = await axios.post(
            'https://sandbox.cashfree.com/payout/transfers',
            {
                transfer_id: "test_transfer_" + Date.now(),
                transfer_amount: 1,
                transfer_currency: "INR",
                transfer_mode: "upi",
                beneficiary_details: {
                    beneficiary_id: "test_ben_1",
                    beneficiary_name: "Test User",
                    beneficiary_instrument_details: {
                        vpa: "success@upi"
                    }
                }
            },
            {
                headers: {
                    'x-client-id': clientId,
                    'x-client-secret': clientSecret,
                    'x-api-version': '2024-01-01',
                    'Content-Type': 'application/json'
                }
            }
        );
        console.log("Success:", response.data);
    } catch (e) {
        console.error("Error:", e.response ? e.response.data : e.message);
    }
}

testCashfree();
