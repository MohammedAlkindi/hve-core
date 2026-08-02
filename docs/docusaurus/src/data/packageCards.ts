// Copyright (c) 2026 Microsoft Corporation. All rights reserved.
// SPDX-License-Identifier: MIT
import { labelRegistry } from './labelRegistry';

export interface PackageCardData {
  name: string;
  title: string;
  description: string;
  artifacts: number;
  maturity: 'Stable' | 'Preview' | 'Experimental';
  href: string;
}

export interface PackageCardDefinition {
  name: string;
  title: string;
  description: string;
  maturity: PackageCardData['maturity'];
  href: string;
}

export const packageCardDefinitions: PackageCardDefinition[] = [
  {
    name: 'ado',
    title: labelRegistry.azureDevOps,
    description: 'Azure DevOps work items, builds, and pull requests',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'coding-standards',
    title: labelRegistry.codingStandards,
    description: 'Language-specific coding conventions',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'data-science',
    title: labelRegistry.dataScience,
    description: 'Data specs, notebooks, and dashboards',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'design-thinking',
    title: labelRegistry.designThinking,
    description: 'AI-enhanced Design Thinking coaching',
    maturity: 'Preview',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'experimental',
    title: labelRegistry.experimentalPackage,
    description: 'Preview artifacts under active development',
    maturity: 'Experimental',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'github',
    title: labelRegistry.github,
    description: 'GitHub issue backlogs and triage workflows',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'gitlab',
    title: labelRegistry.gitlab,
    description: 'GitLab merge requests and pipeline workflows',
    maturity: 'Experimental',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'hve-core',
    title: labelRegistry.hveCore,
    description: 'RPI workflow, planning, and implementation',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'jira',
    title: labelRegistry.jira,
    description: 'Jira backlogs, triage, and PRD-driven planning',
    maturity: 'Experimental',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'project-planning',
    title: labelRegistry.projectPlanning,
    description: 'ADRs, requirements, and architecture diagrams',
    maturity: 'Stable',
    href: '/docs/getting-started/packages',
  },
  {
    name: 'security',
    title: labelRegistry.security,
    description: 'Security review, planning, incident response, and risk assessment',
    maturity: 'Experimental',
    href: '/docs/getting-started/packages',
  },
];

export interface MetaPackages {
  'hve-core-all': number;
}

export function resolvePackageCards(
  counts: Record<string, number>,
): PackageCardData[] {
  return packageCardDefinitions.map((def) => ({
    ...def,
    artifacts: counts[def.name] ?? 0,
  }));
}

export function resolveMetaPackages(
  counts: Record<string, number>,
): MetaPackages {
  return {
    'hve-core-all': counts['hve-core-all'] ?? 0,
  };
}
