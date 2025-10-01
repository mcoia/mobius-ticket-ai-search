// search.component.ts
import { Component, OnInit, OnDestroy } from '@angular/core';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { debounceTime, distinctUntilChanged } from 'rxjs/operators';
import { Subject } from 'rxjs';
import { SearchService, SearchFilters } from '../../services/search.service';
import { Ticket } from '../../models/ticket.model';

@Component({
  standalone: false,
  selector: 'app-search',
  templateUrl: './search.component.html',
  styleUrls: ['./search.component.css']
})
export class SearchComponent implements OnInit, OnDestroy {
  searchTerm: string = '';
  searchResults: Ticket[] = [];
  showResults: boolean = false;
  isLoading: boolean = false;
  private searchTerms = new Subject<string>();
  private subscription: Subscription | null = null;

  // Initialize filters with guaranteed properties to satisfy type safety
  showFilters: boolean = false;
  filters: SearchFilters = this.getEmptyFilters();
  activeFiltersCount: number = 0;
  activeFiltersList: {type: string, value: string, key?: string}[] = [];

  constructor(
    private searchService: SearchService,
    private router: Router
  ) {}

  ngOnInit(): void {
    // Check if there's a saved search from a previous session
    if (this.searchService.lastSearchTerm) {
      this.searchTerm = this.searchService.lastSearchTerm;
      this.searchResults = this.searchService.lastSearchResults;
      this.showResults = this.searchResults.length > 0;

      // Restore last filters safely
      const lastFilters = this.searchService.lastFilters;

      // Set each individual property
      if (lastFilters.queue) {
        this.filters.queue.FOLIO = lastFilters.queue.FOLIO;
        this.filters.queue.OpenRS = lastFilters.queue.OpenRS;
        this.filters.queue.Enhancements = lastFilters.queue.Enhancements;
      }

      if (lastFilters.status) {
        this.filters.status.open = lastFilters.status.open;
        this.filters.status.resolved = lastFilters.status.resolved;
        this.filters.status.stalled = lastFilters.status.stalled;
      }

      if (lastFilters.created) {
        this.filters.created.from = lastFilters.created.from;
        this.filters.created.to = lastFilters.created.to;
      }

      if (lastFilters.updated) {
        this.filters.updated.from = lastFilters.updated.from;
        this.filters.updated.to = lastFilters.updated.to;
      }

      this.updateActiveFiltersCount();

      // If we were redirected back to search with a term, perform a search
      if (this.searchService.wasRedirectedWithTerm) {
        this.executeSearch(this.searchTerm, this.filters);
        this.showResults = true; // Ensure results panel is shown
      }
    }

    // Also check localStorage as a backup mechanism
    const pendingSearchTerm = localStorage.getItem('pendingSearchTerm');
    if (pendingSearchTerm) {
      this.searchTerm = pendingSearchTerm;
      localStorage.removeItem('pendingSearchTerm'); // Clear after use
      this.executeSearch(this.searchTerm, this.filters);
      this.showResults = true;
    }

    // Set up debounced search
    this.subscription = this.searchTerms.pipe(
      debounceTime(300),
      distinctUntilChanged()
    ).subscribe(term => {
      this.executeSearch(term, this.filters);
    });
  }

  ngOnDestroy(): void {
    if (this.subscription) {
      this.subscription.unsubscribe();
    }
  }

  // Get empty filters helper method
  getEmptyFilters(): SearchFilters {
    return {
      queue: {
        FOLIO: false,
        OpenRS: false,
        Enhancements: false
      },
      status: {
        open: false,
        resolved: false,
        stalled: false
      },
      created: {
        from: '',
        to: ''
      },
      updated: {
        from: '',
        to: ''
      }
    };
  }

  // New method to update the activeFiltersList
  updateActiveFiltersList(): void {
    this.activeFiltersList = [];

    // Add queue filters
    Object.entries(this.filters.queue).forEach(([key, value]) => {
      if (value) {
        this.activeFiltersList.push({
          type: 'queue',
          value: `Queue: ${key}`,
          key: key
        });
      }
    });

    // Add status filters
    Object.entries(this.filters.status).forEach(([key, value]) => {
      if (value) {
        this.activeFiltersList.push({
          type: 'status',
          value: `Status: ${key.charAt(0).toUpperCase() + key.slice(1)}`,
          key: key
        });
      }
    });

    // Add date range filters
    if (this.filters.created.from) {
      this.activeFiltersList.push({
        type: 'created',
        value: `Created from: ${this.filters.created.from}`,
        key: 'from'
      });
    }

    if (this.filters.created.to) {
      this.activeFiltersList.push({
        type: 'created',
        value: `Created to: ${this.filters.created.to}`,
        key: 'to'
      });
    }

    if (this.filters.updated.from) {
      this.activeFiltersList.push({
        type: 'updated',
        value: `Updated from: ${this.filters.updated.from}`,
        key: 'from'
      });
    }

    if (this.filters.updated.to) {
      this.activeFiltersList.push({
        type: 'updated',
        value: `Updated to: ${this.filters.updated.to}`,
        key: 'to'
      });
    }
  }

  // Method to count active filters
  updateActiveFiltersCount(): void {
    let count = 0;

    // Count queue filters
    count += Object.values(this.filters.queue).filter(Boolean).length;

    // Count status filters
    count += Object.values(this.filters.status).filter(Boolean).length;

    // Count date filters
    if (this.filters.created.from) count++;
    if (this.filters.created.to) count++;
    if (this.filters.updated.from) count++;
    if (this.filters.updated.to) count++;

    this.activeFiltersCount = count;
  }

  search(term: string): void {
    if (!term.trim()) {
      this.searchResults = [];
      this.showResults = false;
      return;
    }

    // Set loading state immediately
    this.isLoading = true;

    // Update CSS class to show results container (has-results)
    this.showResults = true;

    this.searchTerms.next(term);
  }

  // Method to execute search with filters
  executeSearch(term: string, filters: SearchFilters): void {
    this.isLoading = true;
    this.searchService.searchTickets(term, filters).subscribe({
      next: results => {
        this.searchResults = results;
        this.showResults = true;
        this.isLoading = false;
      },
      error: () => {
        this.isLoading = false;
      }
    });
  }

  handleSearchInputClick(): void {
    // Only show previously cached results if they exist
    if (this.searchResults.length > 0) {
      this.showResults = true;
    }
  }

  updateSearch(term: string): void {
    this.searchTerm = term;
    this.search(term);
    // Close the filter panel when performing a search
    this.showFilters = false;
  }

  // Filter methods
  toggleFilters(event: Event): void {
    event.stopPropagation();
    this.showFilters = !this.showFilters;
  }

  applyFilters(): void {
    // Update the active filters count
    this.updateActiveFiltersCount();
    this.updateActiveFiltersList();

    // Hide the filter panel
    this.showFilters = false;

    // Perform search with current search term and filters
    if (this.searchTerm) {
      this.executeSearch(this.searchTerm, this.filters);
    }
  }

  resetFilters(): void {
    this.filters = this.getEmptyFilters();
    this.updateActiveFiltersCount();
    this.updateActiveFiltersList();

    // If there's a current search, rerun it without filters
    if (this.searchTerm) {
      this.executeSearch(this.searchTerm, this.filters);
    }
  }

  // New method to remove a single filter with proper type safety
  removeFilter(filter: {type: string, value: string, key?: string}): void {
    if (filter.type === 'queue' && filter.key) {
      // Type-safe approach for queue filters
      if (filter.key === 'FOLIO') {
        this.filters.queue.FOLIO = false;
      } else if (filter.key === 'OpenRS') {
        this.filters.queue.OpenRS = false;
      } else if (filter.key === 'Enhancements') {
        this.filters.queue.Enhancements = false;
      }
    } else if (filter.type === 'status' && filter.key) {
      // Type-safe approach for status filters
      if (filter.key === 'open') {
        this.filters.status.open = false;
      } else if (filter.key === 'resolved') {
        this.filters.status.resolved = false;
      } else if (filter.key === 'stalled') {
        this.filters.status.stalled = false;
      }
    } else if (filter.type === 'created') {
      if (filter.key === 'from') {
        this.filters.created.from = '';
      } else if (filter.key === 'to') {
        this.filters.created.to = '';
      }
    } else if (filter.type === 'updated') {
      if (filter.key === 'from') {
        this.filters.updated.from = '';
      } else if (filter.key === 'to') {
        this.filters.updated.to = '';
      }
    }

    this.updateActiveFiltersCount();
    this.updateActiveFiltersList();

    // Rerun search with updated filters
    if (this.searchTerm) {
      this.executeSearch(this.searchTerm, this.filters);
    }
  }
}
