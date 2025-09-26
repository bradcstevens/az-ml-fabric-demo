#!/bin/bash
# Restore claude-code-collective backup from 2025-09-18T01:35:32.362Z

echo "🔄 Restoring claude-code-collective backup..."

# Copy backed up files back to project
cp -r "/Users/bradcstevens/code/github/bradcstevens/az-ml-fabric-demo/.claude-backups/1758159332356/"* "/Users/bradcstevens/code/github/bradcstevens/az-ml-fabric-demo/"

echo "✅ Restored successfully!"
echo "💡 You may need to restart Claude Code to reload configurations."
echo ""
echo "Backup location: /Users/bradcstevens/code/github/bradcstevens/az-ml-fabric-demo/.claude-backups/1758159332356"
