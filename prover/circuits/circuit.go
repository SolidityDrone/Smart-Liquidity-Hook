package age

import (
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
	"fmt"
)

type AppCircuit struct{}

// Constants for the contract and event signatures
var SourceContract = sdk.ConstUint248(
	common.HexToAddress("0xbA68302DA991Edb4892C047cb845045Dd57812b0"))

var LiquidityAddedTopic = sdk.ParseEventID(
	hexutil.MustDecode("0xac1d76749e5447b7b16f5ab61447e1bd502f3bb4807af3b28e620d1700a6ee45"))

var LiquidityRemovedTopic = sdk.ParseEventID(
	hexutil.MustDecode("0x96cd817c6329656790ef8fba7675405193677d39619571282f5e21f3a98cd059"))

var UserAddr = sdk.ConstUint248(
	common.HexToAddress("0xCAc3f7c8C771476251e93B44CB7afA0C2eDd5EB0"))

// Implementing the AppCircuit interface
var _ sdk.AppCircuit = &AppCircuit{}

// Allocate memory for receipts
func (c *AppCircuit) Allocate() (maxReceipts, maxStorage, maxTransactions int) {
	return 2, 0, 0
}

func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	u248 := api.Uint248
	bytes := api.Bytes32
	receipts := sdk.NewDataStream(api, in.Receipts)

	// Initialize variables to track last values
	var lastLiquidity = sdk.ConstUint248(0)
	var lastTimestamp = sdk.ConstUint248(0)
	var cumulativeContribution = sdk.ConstUint248(0)

	// sanity check
	sdk.AssertEach(receipts, func(l sdk.Receipt) sdk.Uint248 {
		assertionPassed := u248.And(
			u248.IsEqual(l.Fields[0].Contract, SourceContract),    
			u248.IsEqual(l.Fields[0].Index, sdk.ConstUint248(1)),  // Field 0 (LogFieldData) should have Index 1
			u248.IsEqual(l.Fields[1].Index, sdk.ConstUint248(2)),  // Field 1 (LogFieldData) should have Index 2
			u248.IsEqual(l.Fields[2].Index, sdk.ConstUint248(3)),  // Field 2 (LogFieldData) should have Index 3
			u248.Or(
				u248.IsEqual(l.Fields[0].EventID, LiquidityAddedTopic),
				u248.IsEqual(l.Fields[0].EventID, LiquidityRemovedTopic),
			),
			u248.Or(
				u248.IsEqual(l.Fields[1].EventID, LiquidityAddedTopic),
				u248.IsEqual(l.Fields[1].EventID, LiquidityRemovedTopic),
			),
			u248.Or(
				u248.IsEqual(l.Fields[2].EventID, LiquidityAddedTopic),
				u248.IsEqual(l.Fields[2].EventID, LiquidityRemovedTopic),
			),
			
		)
		return assertionPassed
	})
	
	// Process receipts
	sdk.Map(receipts, func(cur sdk.Receipt) sdk.Uint248 {
		// Extract current timestamp and liquidity
		currentTimestamp := api.ToUint248(cur.Fields[3].Value)
		currentLiquidity := api.ToUint248(cur.Fields[2].Value)

		// Initialize contribution
		var contribution = sdk.ConstUint248(0)

		// Check if it's a LiquidityAdded event
		if bytes.IsEqual(api.ToBytes32(cur.Fields[0].EventID), api.ToBytes32(LiquidityAddedTopic)) != sdk.ConstUint248(0) {
	
			elapsedTime := u248.Sub(currentTimestamp, lastTimestamp)
			contribution = u248.Mul(lastLiquidity, elapsedTime)
			lastLiquidity = currentLiquidity
			lastTimestamp = currentTimestamp
		} else if bytes.IsEqual(api.ToBytes32(cur.Fields[0].EventID), api.ToBytes32(LiquidityRemovedTopic)) != sdk.ConstUint248(0) {
			elapsedTime := u248.Sub(currentTimestamp, lastTimestamp)
			contribution = u248.Mul(lastLiquidity, elapsedTime)
			lastLiquidity = u248.Sub(lastLiquidity, currentLiquidity)
			lastTimestamp = currentTimestamp
		}

		// Update cumulative contribution
		cumulativeContribution = u248.Add(cumulativeContribution, contribution)

		return contribution
	})

	// Output the cumulative contribution result and user address
	api.OutputUint(256, cumulativeContribution)
	api.OutputAddress(UserAddr)
	api.OutputUint(248, lastLiquidity)
	api.OutputUint(248, lastTimestamp)
	
	return nil
}
