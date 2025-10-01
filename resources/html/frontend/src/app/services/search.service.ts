import {Injectable} from '@angular/core';
import {HttpClient} from '@angular/common/http';
import {Observable, of, throwError} from 'rxjs';
import {catchError, map} from 'rxjs/operators';
import {Ticket} from '../models/ticket.model';

// Define a new interface for filter parameters
export interface SearchFilters {
  queue: {
    FOLIO: boolean;
    OpenRS: boolean;
    Enhancements: boolean;
  };
  status: {
    open: boolean;
    resolved: boolean;
    stalled: boolean;
  };
  created: {
    from: string;
    to: string;
  };
  updated: {
    from: string;
    to: string;
  };
}

@Injectable({
  providedIn: 'root'
})
export class SearchService {
  // private apiUrl = 'http://localhost:10000'; // <== Development
  private apiUrl = ''; // <== Production

  // Add properties to store search state
  private _lastSearchTerm: string = '';
  private _lastSearchResults: Ticket[] = [];
  private _pendingSearchTerm: string = '';
  private _wasRedirectedWithTerm: boolean = false;
  private _lastFilters: SearchFilters = this.getEmptyFilters(); // Add filter state

  constructor(private http: HttpClient) {
  }

  // Create a method to get empty filters to avoid code duplication
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

  // Getters for the saved search state
  get lastSearchTerm(): string {
    // If there is a pending search term from ticket detail, use it
    if (this._pendingSearchTerm) {
      const term = this._pendingSearchTerm;
      this._pendingSearchTerm = ''; // Clear it after use
      this._wasRedirectedWithTerm = true; // Set the flag when we actually return the pending term
      return term;
    }
    return this._lastSearchTerm;
  }

  get lastSearchResults(): Ticket[] {
    return this._lastSearchResults;
  }

  get wasRedirectedWithTerm(): boolean {
    const wasRedirected = this._wasRedirectedWithTerm;
    this._wasRedirectedWithTerm = false; // Reset after checking
    return wasRedirected;
  }

  // New getter for last filters
  get lastFilters(): SearchFilters {
    return this._lastFilters;
  }

  // New method to set a search term to be used when returning to search
  setSearchTerm(term: string): void {
    this._pendingSearchTerm = term;
    this._lastSearchResults = []; // Clear previous results to force a new search
  }

  // Save search state when searching
  searchTickets(searchTerm: string, filters?: SearchFilters): Observable<Ticket[]> {
    if (!searchTerm.trim()) {
      this._lastSearchTerm = '';
      this._lastSearchResults = [];
      return of([]);
    }

    // Save the search term and filters immediately
    this._lastSearchTerm = searchTerm;
    if (filters) {
      this._lastFilters = {...filters};
    }

    // Build the request payload
    const payload: any = {searchTerm};

    // Add filters to the payload if they exist
    if (filters) {
      payload.filters = this.prepareFiltersForApi(filters);
    }

    return this.http.post<{ hits: Ticket[] }>(`${this.apiUrl}/api/search`, payload)
      .pipe(
        catchError(this.handleError<{ hits: Ticket[] }>('searchTickets', {hits: []})),
        map(response => {
          // Save the search results when they arrive
          this._lastSearchResults = response.hits || [];
          return this._lastSearchResults;
        })
      );
  }

  // Helper method to prepare filters for API request
  // This converts the filter object to a format suitable for the backend
  private prepareFiltersForApi(filters: SearchFilters): any {
    const apiFilters: any = {};

    // Process queue filters
    if (filters.queue) {
      const selectedQueues = Object.entries(filters.queue)
        .filter(([_, selected]) => selected)
        .map(([queue, _]) => queue);

      if (selectedQueues.length > 0) {
        apiFilters.queue = selectedQueues;
      }
    }

    // Process status filters
    if (filters.status) {
      const selectedStatuses = Object.entries(filters.status)
        .filter(([_, selected]) => selected)
        .map(([status, _]) => status);

      if (selectedStatuses.length > 0) {
        apiFilters.status = selectedStatuses;
      }
    }

    // Process date filters (only include if there's a value)
    if (filters.created) {
      apiFilters.created = {};
      if (filters.created.from) apiFilters.created.from = filters.created.from;
      if (filters.created.to) apiFilters.created.to = filters.created.to;

      // Remove empty object if no dates were set
      if (Object.keys(apiFilters.created).length === 0) {
        delete apiFilters.created;
      }
    }

    if (filters.updated) {
      apiFilters.updated = {};
      if (filters.updated.from) apiFilters.updated.from = filters.updated.from;
      if (filters.updated.to) apiFilters.updated.to = filters.updated.to;

      // Remove empty object if no dates were set
      if (Object.keys(apiFilters.updated).length === 0) {
        delete apiFilters.updated;
      }
    }

    return apiFilters;
  }

  getTicketById(id: number): Observable<Ticket> {
    return this.http.get<Ticket>(`${this.apiUrl}/api/ticket/${id}`)
      .pipe(
        catchError(error => {
          console.error(`Error fetching ticket #${id}:`, error);
          return throwError(() => new Error('Failed to load ticket details'));
        })
      );
  }

  clearSearchState(): void {
    this._lastSearchTerm = '';
    this._lastSearchResults = [];
    this._pendingSearchTerm = '';
    this._wasRedirectedWithTerm = false;
    this._lastFilters = this.getEmptyFilters(); // Clear filters
  }

  private handleError<T>(operation = 'operation', result?: T) {
    return (error: any): Observable<T> => {
      console.error(`${operation} failed: ${error.message}`);
      // Return an empty result to keep the application running
      return of(result as T);
    };
  }
}
