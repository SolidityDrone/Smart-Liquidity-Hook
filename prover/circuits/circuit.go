package age

import (
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
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
	return 10, 0, 0
}

// Define the circuit behavior and calculate contribution points
func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	u248 := api.Uint248
	bytes := api.Bytes32 
	receipts := sdk.NewDataStream(api, in.Receipts)

	var cumulativeContribution sdk.Uint248
	var lastLiquidity sdk.Uint248
	var lastTimestamp sdk.Uint248
	var zero sdk.Uint248

	// Iterate through each receipt to assert conditions
	sdk.AssertEach(receipts, func(l sdk.Receipt) sdk.Uint248 {
		assertionPassed := u248.And(
			u248.IsEqual(l.Fields[0].Contract, SourceContract),
			u248.IsEqual(l.Fields[1].Index, sdk.ConstUint248(1)),
			u248.IsEqual(l.Fields[2].Index, sdk.ConstUint248(2)),
			u248.IsEqual(l.Fields[3].Index, sdk.ConstUint248(3)),
		)
		return assertionPassed
	})


	// Process receipts to calculate contribution points
	_ = sdk.Map(receipts, func(l sdk.Receipt) sdk.Uint248 {
		// Check if Fields has enough elements
		if len(l.Fields) < 4 {
			// Log an error or handle appropriately
			return sdk.ConstUint248(0) // Or any default value
		}
		
		// Extract the current timestamp and liquidity safely
		currentTimestamp := api.ToUint248(l.Fields[3].Value) // Assuming index 3 is the time field
		currentLiquidity := api.ToUint248(l.Fields[2].Value) // Assuming index 2 is the liquidity field

		// Initialize contribution points for this receipt
		var contribution sdk.Uint248

		// Check if it's a LiquidityAdded event
		if bytes.IsEqual(api.ToBytes32(l.Fields[0].EventID), api.ToBytes32(LiquidityAddedTopic)) != zero {
			if u248.IsZero(lastTimestamp) == zero {
				// Calculate elapsed time since the last event
				elapsedTime := u248.Sub(currentTimestamp, lastTimestamp)
				// Calculate contribution points for the last liquidity
				contribution = u248.Mul(lastLiquidity, elapsedTime)
			}
			lastLiquidity = currentLiquidity
			lastTimestamp = currentTimestamp
		} else if bytes.IsEqual(api.ToBytes32(l.Fields[0].EventID), api.ToBytes32(LiquidityRemovedTopic)) != zero {
			if u248.IsZero(lastTimestamp) == zero {
				// Calculate elapsed time since the last event
				elapsedTime := u248.Sub(currentTimestamp, lastTimestamp)
				contribution = u248.Mul(lastLiquidity, elapsedTime)
			}
			lastLiquidity = u248.Sub(lastLiquidity, currentLiquidity)
			lastTimestamp = currentTimestamp
		}

		// Update cumulative contribution
		cumulativeContribution = u248.Add(cumulativeContribution, contribution)

		return contribution
	})

	// Output the cumulative contribution points
	api.OutputUint(248, cumulativeContribution)
	api.OutputAddress(UserAddr)

	return nil
}
