#!/usr/bin/env node

/**
 * Plus1 Enforcement - Ruleset Manager
 * 
 * Node.js script for managing GitHub Enterprise repository rulesets
 * based on Datadog YAML lifecycle configurations.
 */

const { Octokit } = require('@octokit/rest');
const yaml = require('js-yaml');
const fs = require('fs').promises;
const path = require('path');

// Configuration
const CONFIG = {
    rulesetName: 'plus1_enforcement',
    datadogYamlPath: 'entity.datadog.yaml',
    productionLifecycleValues: ['production', 'Production'],
    batchSize: 10,
    retryAttempts: 3,
    retryDelay: 1000, // ms
    apiVersion: 'v3.0'
};

class RulesetManager {
    constructor(token, organization, options = {}) {
        this.octokit = new Octokit({ auth: token });
        this.organization = organization;
        this.options = { ...CONFIG, ...options };
        this.dryRun = options.dryRun || false;
        this.verbose = options.verbose || false;
        
        this.stats = {
            totalRepositories: 0,
            productionRepositories: 0,
            nonProductionRepositories: 0,
            skippedArchived: 0,
            noDatadogYaml: 0,
            invalidSchema: 0,
            noLifecycle: 0,
            errors: 0,
            reposToAdd: 0,
            reposToRemove: 0
        };
    }

    /**
     * Log message with timestamp and level
     */
    log(level, message, data = null) {
        const timestamp = new Date().toISOString();
        const prefix = `[${timestamp}] [${level.toUpperCase()}]`;
        
        if (level === 'verbose' && !this.verbose) return;
        
        console.log(`${prefix} ${message}`);
        if (data && this.verbose) {
            console.log(JSON.stringify(data, null, 2));
        }
    }

    /**
     * Sleep for specified milliseconds
     */
    async sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Retry an async operation with exponential backoff
     */
    async retry(operation, attempts = this.options.retryAttempts) {
        for (let i = 0; i < attempts; i++) {
            try {
                return await operation();
            } catch (error) {
                if (i === attempts - 1) throw error;
                
                const delay = this.options.retryDelay * Math.pow(2, i);
                this.log('verbose', `Attempt ${i + 1} failed, retrying in ${delay}ms`, { error: error.message });
                await this.sleep(delay);
            }
        }
    }

    /**
     * Get all repositories in the organization
     */
    async getAllRepositories() {
        this.log('info', `Fetching all repositories for organization: ${this.organization}`);
        
        const repositories = await this.octokit.paginate(
            this.octokit.rest.repos.listForOrg,
            {
                org: this.organization,
                type: 'all',
                per_page: 100
            }
        );

        this.stats.totalRepositories = repositories.length;
        this.log('info', `Found ${repositories.length} repositories`);
        
        return repositories;
    }

    /**
     * Analyze a single repository for Datadog YAML and lifecycle
     */
    async analyzeRepository(repo) {
        const analysis = {
            name: repo.name,
            status: 'unknown',
            reason: '',
            lifecycle: null,
            isProduction: false
        };

        try {
            // Skip archived repositories
            if (repo.archived) {
                analysis.status = 'skipped';
                analysis.reason = 'Repository is archived';
                this.stats.skippedArchived++;
                return analysis;
            }

            // Fetch Datadog YAML file
            let datadogYaml;
            try {
                const response = await this.retry(async () => {
                    return await this.octokit.rest.repos.getContent({
                        owner: this.organization,
                        repo: repo.name,
                        path: this.options.datadogYamlPath
                    });
                });

                if (response.data.type !== 'file') {
                    throw new Error('Not a file');
                }

                const content = Buffer.from(response.data.content, 'base64').toString('utf-8');
                datadogYaml = yaml.load(content);
            } catch (error) {
                if (error.status === 404) {
                    analysis.status = 'no_datadog_yaml';
                    analysis.reason = `No ${this.options.datadogYamlPath} file found`;
                    this.stats.noDatadogYaml++;
                    return analysis;
                }
                throw error;
            }

            // Validate schema version
            if (!datadogYaml.apiVersion || !datadogYaml.apiVersion.startsWith(this.options.apiVersion)) {
                analysis.status = 'invalid_schema';
                analysis.reason = `Invalid or missing apiVersion (expected ${this.options.apiVersion}, got: ${datadogYaml.apiVersion})`;
                analysis.lifecycle = datadogYaml.spec?.lifecycle || null;
                this.stats.invalidSchema++;
                return analysis;
            }

            // Extract lifecycle
            const lifecycle = datadogYaml.spec?.lifecycle;
            if (!lifecycle) {
                analysis.status = 'no_lifecycle';
                analysis.reason = 'No lifecycle specified in spec.lifecycle';
                this.stats.noLifecycle++;
                return analysis;
            }

            analysis.lifecycle = lifecycle;

            // Check if production
            const isProduction = this.options.productionLifecycleValues.includes(lifecycle);
            analysis.isProduction = isProduction;

            if (isProduction) {
                analysis.status = 'production';
                analysis.reason = `Lifecycle: ${lifecycle}`;
                this.stats.productionRepositories++;
            } else {
                analysis.status = 'non_production';
                analysis.reason = `Lifecycle: ${lifecycle}`;
                this.stats.nonProductionRepositories++;
            }

        } catch (error) {
            this.log('error', `Error analyzing repository ${repo.name}`, { error: error.message });
            analysis.status = 'error';
            analysis.reason = error.message;
            this.stats.errors++;
        }

        return analysis;
    }

    /**
     * Analyze all repositories in batches
     */
    async analyzeAllRepositories(repositories) {
        this.log('info', `Analyzing ${repositories.length} repositories in batches of ${this.options.batchSize}`);
        
        const results = [];
        
        for (let i = 0; i < repositories.length; i += this.options.batchSize) {
            const batch = repositories.slice(i, i + this.options.batchSize);
            this.log('verbose', `Processing batch ${Math.floor(i / this.options.batchSize) + 1}`);
            
            const batchPromises = batch.map(repo => this.analyzeRepository(repo));
            const batchResults = await Promise.all(batchPromises);
            
            results.push(...batchResults);
            
            // Rate limiting delay between batches
            if (i + this.options.batchSize < repositories.length) {
                await this.sleep(1000);
            }
        }

        return results;
    }

    /**
     * Get current ruleset configuration
     */
    async getCurrentRuleset() {
        this.log('info', `Looking for ruleset: ${this.options.rulesetName}`);
        
        try {
            const rulesets = await this.retry(async () => {
                return await this.octokit.rest.repos.getOrgRulesets({
                    org: this.organization
                });
            });

            const targetRuleset = rulesets.data.find(r => r.name === this.options.rulesetName);
            
            if (!targetRuleset) {
                this.log('warning', `Ruleset '${this.options.rulesetName}' not found`);
                return {
                    exists: false,
                    id: null,
                    currentTargets: []
                };
            }

            this.log('info', `Found ruleset: ${targetRuleset.name} (ID: ${targetRuleset.id})`);

            // Get detailed ruleset information
            const rulesetDetails = await this.retry(async () => {
                return await this.octokit.rest.repos.getOrgRuleset({
                    org: this.organization,
                    ruleset_id: targetRuleset.id
                });
            });

            // Extract current targets
            const currentTargets = [];
            if (rulesetDetails.data.conditions?.repository_name?.include) {
                currentTargets.push(...rulesetDetails.data.conditions.repository_name.include);
            }

            this.log('verbose', `Current targets: ${currentTargets.join(', ')}`);

            return {
                exists: true,
                id: targetRuleset.id,
                currentTargets,
                details: rulesetDetails.data
            };

        } catch (error) {
            if (error.status === 404) {
                this.log('warning', `Ruleset '${this.options.rulesetName}' not found`);
                return {
                    exists: false,
                    id: null,
                    currentTargets: []
                };
            }
            throw error;
        }
    }

    /**
     * Calculate required changes to ruleset
     */
    calculateChanges(analysisResults, currentRuleset) {
        const productionRepos = analysisResults
            .filter(r => r.status === 'production')
            .map(r => r.name)
            .sort();

        const currentTargets = currentRuleset.currentTargets || [];
        
        const reposToAdd = productionRepos.filter(repo => !currentTargets.includes(repo));
        const reposToRemove = currentTargets.filter(repo => !productionRepos.includes(repo));
        
        this.stats.reposToAdd = reposToAdd.length;
        this.stats.reposToRemove = reposToRemove.length;

        const changes = {
            requiresUpdate: reposToAdd.length > 0 || reposToRemove.length > 0,
            reposToAdd,
            reposToRemove,
            newTargets: productionRepos,
            currentTargets
        };

        this.log('info', `Change analysis complete:`, {
            requiresUpdate: changes.requiresUpdate,
            reposToAdd: changes.reposToAdd.length,
            reposToRemove: changes.reposToRemove.length,
            newTargets: changes.newTargets.length,
            currentTargets: changes.currentTargets.length
        });

        if (changes.reposToAdd.length > 0) {
            this.log('info', `Repositories to add: ${changes.reposToAdd.join(', ')}`);
        }

        if (changes.reposToRemove.length > 0) {
            this.log('info', `Repositories to remove: ${changes.reposToRemove.join(', ')}`);
        }

        return changes;
    }

    /**
     * Update the ruleset with new targets
     */
    async updateRuleset(currentRuleset, changes) {
        if (!changes.requiresUpdate) {
            this.log('info', 'No changes required to ruleset');
            return { updated: false, reason: 'No changes required' };
        }

        if (!currentRuleset.exists) {
            const message = `Ruleset '${this.options.rulesetName}' does not exist. Please create it manually first.`;
            this.log('error', message);
            throw new Error(message);
        }

        if (this.dryRun) {
            this.log('info', `DRY RUN: Would update ruleset with ${changes.newTargets.length} targets`);
            this.log('info', `DRY RUN: Would add ${changes.reposToAdd.length} repositories`);
            this.log('info', `DRY RUN: Would remove ${changes.reposToRemove.length} repositories`);
            return { updated: false, reason: 'Dry run mode' };
        }

        this.log('info', `Updating ruleset: ${this.options.rulesetName}`);

        try {
            // Prepare updated conditions
            const updatedConditions = {
                ...currentRuleset.details.conditions,
                repository_name: {
                    include: changes.newTargets,
                    exclude: currentRuleset.details.conditions?.repository_name?.exclude || []
                }
            };

            await this.retry(async () => {
                return await this.octokit.rest.repos.updateOrgRuleset({
                    org: this.organization,
                    ruleset_id: currentRuleset.id,
                    name: currentRuleset.details.name,
                    target: currentRuleset.details.target,
                    enforcement: currentRuleset.details.enforcement,
                    conditions: updatedConditions,
                    rules: currentRuleset.details.rules,
                    bypass_actors: currentRuleset.details.bypass_actors
                });
            });

            this.log('info', `Successfully updated ruleset: ${this.options.rulesetName}`);
            this.log('info', `Added ${changes.reposToAdd.length} repositories`);
            this.log('info', `Removed ${changes.reposToRemove.length} repositories`);
            this.log('info', `Total targets: ${changes.newTargets.length}`);

            return { 
                updated: true, 
                reposAdded: changes.reposToAdd.length,
                reposRemoved: changes.reposToRemove.length,
                totalTargets: changes.newTargets.length
            };

        } catch (error) {
            this.log('error', `Failed to update ruleset: ${error.message}`);
            throw error;
        }
    }

    /**
     * Generate a comprehensive report
     */
    generateReport(analysisResults, changes, updateResult) {
        const report = {
            timestamp: new Date().toISOString(),
            organization: this.organization,
            rulesetName: this.options.rulesetName,
            dryRun: this.dryRun,
            statistics: this.stats,
            analysis: {
                totalRepositories: analysisResults.length,
                productionRepositories: analysisResults.filter(r => r.status === 'production').length,
                byStatus: analysisResults.reduce((acc, r) => {
                    acc[r.status] = (acc[r.status] || 0) + 1;
                    return acc;
                }, {})
            },
            changes: {
                requiresUpdate: changes.requiresUpdate,
                reposToAdd: changes.reposToAdd,
                reposToRemove: changes.reposToRemove,
                newTargetCount: changes.newTargets.length,
                currentTargetCount: changes.currentTargets.length
            },
            updateResult: updateResult || { updated: false, reason: 'Update not attempted' }
        };

        return report;
    }

    /**
     * Main execution function
     */
    async run() {
        try {
            this.log('info', `Starting Plus1 Enforcement analysis for organization: ${this.organization}`);
            this.log('info', `Configuration:`, {
                rulesetName: this.options.rulesetName,
                datadogYamlPath: this.options.datadogYamlPath,
                productionLifecycleValues: this.options.productionLifecycleValues,
                dryRun: this.dryRun
            });

            // Get all repositories
            const repositories = await this.getAllRepositories();

            // Analyze repositories
            const analysisResults = await this.analyzeAllRepositories(repositories);

            // Get current ruleset
            const currentRuleset = await this.getCurrentRuleset();

            // Calculate changes
            const changes = this.calculateChanges(analysisResults, currentRuleset);

            // Update ruleset if needed
            let updateResult = null;
            if (changes.requiresUpdate || this.dryRun) {
                updateResult = await this.updateRuleset(currentRuleset, changes);
            }

            // Generate report
            const report = this.generateReport(analysisResults, changes, updateResult);

            this.log('info', 'Plus1 Enforcement analysis complete');
            this.log('info', `Statistics:`, this.stats);

            return report;

        } catch (error) {
            this.log('error', `Plus1 Enforcement failed: ${error.message}`);
            throw error;
        }
    }
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);
    
    if (args.includes('--help') || args.includes('-h')) {
        console.log(`
Plus1 Enforcement Ruleset Manager

Usage: node ruleset-manager.js [options]

Options:
  --token <token>        GitHub token (or set GITHUB_TOKEN env var)
  --org <organization>   GitHub organization name
  --dry-run              Perform a dry run without making changes
  --verbose              Enable verbose logging
  --ruleset <name>       Ruleset name (default: plus1_enforcement)
  --yaml-path <path>     Path to Datadog YAML file (default: entity.datadog.yaml)
  --output <file>        Save report to JSON file
  --help                 Show this help message

Examples:
  node ruleset-manager.js --org myorg --token ghp_xxx
  node ruleset-manager.js --org myorg --dry-run --verbose
  node ruleset-manager.js --org myorg --output report.json
        `);
        process.exit(0);
    }

    const token = args[args.indexOf('--token') + 1] || process.env.GITHUB_TOKEN;
    const organization = args[args.indexOf('--org') + 1] || process.env.GITHUB_ORG;
    const dryRun = args.includes('--dry-run');
    const verbose = args.includes('--verbose');
    const outputFile = args.includes('--output') ? args[args.indexOf('--output') + 1] : null;

    const options = {};
    if (args.includes('--ruleset')) {
        options.rulesetName = args[args.indexOf('--ruleset') + 1];
    }
    if (args.includes('--yaml-path')) {
        options.datadogYamlPath = args[args.indexOf('--yaml-path') + 1];
    }

    if (!token) {
        console.error('Error: GitHub token is required. Use --token or set GITHUB_TOKEN environment variable.');
        process.exit(1);
    }

    if (!organization) {
        console.error('Error: Organization is required. Use --org or set GITHUB_ORG environment variable.');
        process.exit(1);
    }

    const manager = new RulesetManager(token, organization, {
        ...options,
        dryRun,
        verbose
    });

    try {
        const report = await manager.run();
        
        if (outputFile) {
            await fs.writeFile(outputFile, JSON.stringify(report, null, 2));
            console.log(`Report saved to: ${outputFile}`);
        }

        process.exit(0);
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

// Export for use as module
module.exports = { RulesetManager, CONFIG };

// Run CLI if this file is executed directly
if (require.main === module) {
    main().catch(error => {
        console.error('Unhandled error:', error);
        process.exit(1);
    });
}