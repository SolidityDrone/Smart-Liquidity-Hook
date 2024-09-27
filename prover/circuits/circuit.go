package age

import (
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
)

type AppCircuit struct{}

var LiquidityToken = sdk.ConstUint248(
	common.HexToAddress("0x5698BAd447b8453E698E2c5992530f6764Aa795e"))

var TranferEventTopic0 = sdk.ParseEventID(
	hexutil.MustDecode("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"))

var User = sdk.ConstUint248(
		common.HexToAddress("0xa62eeb0e29007c75130bcf74a128e524d8ecbb10"))

func (c *AppCircuit) Allocate() (maxReceipts, maxStorage, maxTransactions int) {
	// Our app is only ever going to use one storage data at a time so
	// we can simply limit the max number of data for storage to 1 and
	// 0 for all others
	return 1, 0, 0
}

func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	u248 := api.Uint248
	receipts := sdk.NewDataStream(api, in.Receipts)

	// Iterate through the receipts and extract the required information
	sdk.AssertEach(receipts, func(l sdk.Receipt) sdk.Uint248 {
		// Perform assertions
		assertionPassed := u248.And(
			u248.IsEqual(l.Fields[0].Contract, LiquidityToken),
			u248.IsEqual(l.Fields[0].EventID, TranferEventTopic0),
			u248.IsEqual(l.Fields[0].Index, sdk.ConstUint248(2)),
			u248.IsEqual(api.ToUint248(l.Fields[0].Value), User),
		)

	
		return assertionPassed
	})

	api.OutputAddress(User)


	return nil
}
