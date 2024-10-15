package age

import (
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/hexutil"
)

// AppCircuit defines the structure of the circuit.
type AppCircuit struct{}

// Constants for the contract and event signatures
var (
	SourceContract = sdk.ConstUint248(
		common.HexToAddress("0xbA68302DA991Edb4892C047cb845045Dd57812b0"),
	)

	LiquidityAddedTopic = sdk.ParseEventID(
		hexutil.MustDecode("0xac1d76749e5447b7b16f5ab61447e1bd502f3bb4807af3b28e620d1700a6ee45"),
	)

	LiquidityRemovedTopic = sdk.ParseEventID(
		hexutil.MustDecode("0x96cd817c6329656790ef8fba7675405193677d39619571282f5e21f3a98cd059"),
	)

	UserAddr = sdk.ConstUint248(
		common.HexToAddress("0xCAc3f7c8C771476251e93B44CB7afA0C2eDd5EB0"),
	)
)

// Ensure AppCircuit implements the sdk.AppCircuit interface
var _ sdk.AppCircuit = &AppCircuit{}

// Allocate memory for receipts
func (c *AppCircuit) Allocate() (maxReceipts, maxStorage, maxTransactions int) {
	return 2, 0, 0 // Allocate space for 2 receipts, no storage, no transactions
}

// Define the circuit logic
func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	u248 := api.Uint248      	// Alias for Uint248 functions
	bytes := api.Bytes32      	// Alias for Bytes32 functions
	receipts := sdk.NewDataStream(api, in.Receipts)

	// Initialize variables to track last values
	var (
		lastLiquidity           = sdk.ConstUint248(0) 	// Track last liquidity amount
		lastTimestamp          = sdk.ConstUint248(0) 	// Track last timestamp
		cumulativeContribution  = sdk.ConstUint248(0) 	// Track cumulative contributions
	)

	// Sanity check on the receipts to ensure they contain valid data
	sdk.AssertEach(receipts, func(l sdk.Receipt) sdk.Uint248 {
		assertionPassed := u248.And(
			u248.IsEqual(l.Fields[0].Contract, SourceContract),    			// Check if the contract matches
			u248.IsEqual(l.Fields[0].Index, sdk.ConstUint248(1)),  			// Field 0 should have Index 1
			u248.IsEqual(l.Fields[1].Index, sdk.ConstUint248(2)),  			// Field 1 should have Index 2
			u248.IsEqual(l.Fields[2].Index, sdk.ConstUint248(3)),  			// Field 2 should have Index 3
			u248.Or(
				u248.IsEqual(l.Fields[0].EventID, LiquidityAddedTopic), 	// Check if event ID is LiquidityAdded
				u248.IsEqual(l.Fields[0].EventID, LiquidityRemovedTopic), 	// Check if event ID is LiquidityRemoved
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
		return assertionPassed // Return whether the assertion passed
	})

	// Process receipts to calculate contributions
	sdk.Map(receipts, func(cur sdk.Receipt) sdk.Uint248 {
		// Extract current timestamp and liquidity from the receipt
		currentTimestamp := api.ToUint248(cur.Fields[3].Value)
		currentLiquidity := api.ToUint248(cur.Fields[2].Value)

		// Initialize contribution for the current event
		var contribution = sdk.ConstUint248(0)

		// Check if it's a LiquidityAdded event
		if bytes.IsEqual(api.ToBytes32(cur.Fields[0].EventID), api.ToBytes32(LiquidityAddedTopic)) != sdk.ConstUint248(0) {
			elapsedTime := u248.Sub(currentTimestamp, lastTimestamp) 	// Calculate elapsed time
			contribution = u248.Mul(lastLiquidity, elapsedTime)      	// Calculate contribution
			lastLiquidity = currentLiquidity                           	// Update last liquidity
			lastTimestamp = currentTimestamp                           	// Update last timestamp
		} else if bytes.IsEqual(api.ToBytes32(cur.Fields[0].EventID), api.ToBytes32(LiquidityRemovedTopic)) != sdk.ConstUint248(0) {
			elapsedTime := u248.Sub(currentTimestamp, lastTimestamp) 	// Calculate elapsed time
			contribution = u248.Mul(lastLiquidity, elapsedTime)      	// Calculate contribution
			lastLiquidity = u248.Sub(lastLiquidity, currentLiquidity) 	// Update last liquidity after removal
			lastTimestamp = currentTimestamp                           	// Update last timestamp
		}

		// Update cumulative contribution
		cumulativeContribution = u248.Add(cumulativeContribution, contribution)

		return contribution // Return the contribution for the current receipt
	})

	// Output the cumulative contribution result and user address
	api.OutputUint(256, cumulativeContribution) 	// Output cumulative contribution
	api.OutputAddress(UserAddr)                  	// Output user address
	api.OutputUint(248, lastLiquidity)            	// Output last liquidity
	api.OutputUint(248, lastTimestamp)            	// Output last timestamp

	return nil // Return nil to indicate success
}
