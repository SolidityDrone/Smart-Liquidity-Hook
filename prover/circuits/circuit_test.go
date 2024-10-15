package age

import (
	"math/big"
	"testing"
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/brevis-network/brevis-sdk/test"
	"github.com/ethereum/go-ethereum/common"
)

func TestCircuit(t *testing.T) {
	app, err := sdk.NewBrevisApp()
	check(err)

	// Add the provided receipts to the test

	// First receipt data
	contract1 := common.HexToAddress("0xbA68302DA991Edb4892C047cb845045Dd57812b0")
	eventID1 := common.HexToHash("0xac1d76749e5447b7b16f5ab61447e1bd502f3bb4807af3b28e620d1700a6ee45")
	app.AddReceipt(sdk.ReceiptData{
		BlockNum: big.NewInt(6771349),
		TxHash:   common.HexToHash("0x31834e3dac9102c89290d60a48a8c71b6d9a27371e7a66c48b4494261d70f85b"),
		Fields: [sdk.NumMaxLogFields]sdk.LogFieldData{
			{
				Contract:   contract1,
				LogIndex:   25,
				EventID:    eventID1,
				IsTopic:    true,
				FieldIndex: 1,
				Value:      common.HexToHash("0xCAc3f7c8C771476251e93B44CB7afA0C2eDd5EB0"),
			},
			{
				Contract:   contract1,
				LogIndex:   25,
				EventID:    eventID1,
				FieldIndex: 2,
				IsTopic:    false,
				Value:      common.BigToHash(big.NewInt(15000)),
			},
			{
				Contract:   contract1,
				LogIndex:   25,
				EventID:    eventID1,
				FieldIndex: 3,
				IsTopic:    false,
				Value:      common.BigToHash(big.NewInt(1727473536)),
			},
		},
	})

	// Second receipt data
	contract2 := common.HexToAddress("0xbA68302DA991Edb4892C047cb845045Dd57812b0")
	eventID2 := common.HexToHash("0x96cd817c6329656790ef8fba7675405193677d39619571282f5e21f3a98cd059")
	app.AddReceipt(sdk.ReceiptData{
		BlockNum: big.NewInt(6771350),
		TxHash:   common.HexToHash("0x5dce903b6e340fa4a47bc0c23099d39ff7d9206eeb3d83f9a22355890bbd4d79"),
		Fields: [sdk.NumMaxLogFields]sdk.LogFieldData{
			{
				Contract:   contract2,
				LogIndex:   64,
				EventID:    eventID2,
				IsTopic:    true,
				FieldIndex: 1,
				Value:      common.HexToHash("0xCAc3f7c8C771476251e93B44CB7afA0C2eDd5EB0"),
			},
			{
				Contract:   contract2,
				LogIndex:   64,
				EventID:    eventID2,
				IsTopic:    false,
				FieldIndex: 2,
				Value:      common.BigToHash(big.NewInt(10000)),
			},
			{
				Contract:   contract2,
				LogIndex:   64,
				EventID:    eventID2,
				IsTopic:    false,
				FieldIndex: 3,
				Value:      common.BigToHash(big.NewInt(1728337548)),
			},
		},
	})

	// Initialize the AppCircuit and prepare the circuit assignment
	guest := &AppCircuit{}
	guestAssignment := &AppCircuit{}

	// Execute the added queries and package the query results into circuit inputs
	circuitInput, err := app.BuildCircuitInput(guest)
	check(err)

	// Testing with ProverSucceeded
	test.ProverSucceeded(t, guest, guestAssignment, circuitInput)
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
