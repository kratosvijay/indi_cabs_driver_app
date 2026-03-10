const axios = require('axios');

async function testCashfree() {
    const clientId = "CF1221593D6O0DRN1JLGC7391N4DG";
    const clientSecret = "cfsk_ma_prod_6cd6a70049ee342ff9cf855781ca03ea_39219573";

    try {
        const response = await axios.post(
            'https://payout-api.cashfree.com/payout/transfers',
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
